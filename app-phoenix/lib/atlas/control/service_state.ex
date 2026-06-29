defmodule Atlas.Control.ServiceState do
  @moduledoc """
  Per-service stateful actor.

  Holds hot-path state (status, phase, progress, last_log) for one upstream
  service in memory. The actor is registered under `Atlas.Control.Registry`
  via the service name, so callers address it as
  `{:via, Registry, {Atlas.Control.Registry, name}}`.

  ## Lifecycle

    * `init/1` hydrates from the `services` table.
    * `feed/2` (cast) pipes a log line through the configured parser and
      broadcasts a snapshot on `control:service:<name>` (and a fan-in tick
      on `control:status`) whenever the snapshot changes.
    * `enable/1` and `disable/1` (call) flip `services.enabled` and run the
      corresponding `docker compose` command.

  User-set fields (e.g. `enabled`) are persisted immediately. Ephemeral
  parser-derived fields (phase/progress/last_log) are batched and flushed by
  `Atlas.Control.SnapshotPersister`; we just mark `pending_persist?: true`
  so the persister knows to write us back.
  """

  use GenServer

  alias Atlas.Control.{Registry, Service}
  alias Atlas.Repo
  alias Phoenix.PubSub

  defstruct [
    :name,
    :profile,
    :parser_mod,
    :parser_acc,
    :status,
    :phase,
    :progress,
    :last_log,
    :ready?,
    :disk_bytes,
    :last_seen_at,
    :enabled?,
    :auto_update_enabled?,
    :update_status,
    :last_error,
    :pending_persist?,
    :compose_ref
  ]

  ## Public API

  def start_link({name, profile, parser_mod}) do
    GenServer.start_link(__MODULE__, {name, profile, parser_mod}, name: Registry.via(name))
  end

  def feed(name, line), do: GenServer.cast(Registry.via(name), {:feed, line})
  def snapshot(name), do: GenServer.call(Registry.via(name), :snapshot)
  def enable(name), do: GenServer.call(Registry.via(name), :enable)
  def disable(name), do: GenServer.call(Registry.via(name), :disable)

  @doc """
  Compare desired state (the persisted `enabled` flag) against the actual
  container and converge: start enabled services whose container is gone
  (compose down, host redeploy), correct stale running-ish statuses, and
  attach a log tailer to running services so the parser keeps deriving
  status/progress. Called for every service at boot.
  """
  def reconcile(name), do: GenServer.cast(Registry.via(name), :reconcile)
  def begin_update(name), do: GenServer.call(Registry.via(name), :begin_update)
  def finish_update(name, opts), do: GenServer.cast(Registry.via(name), {:finish_update, opts})
  def set_auto_update(name, enabled), do: GenServer.call(Registry.via(name), {:set_auto_update, enabled})

  ## Callbacks

  @impl true
  def init({name, profile, parser_mod}) do
    state = %__MODULE__{
      name: name,
      profile: profile,
      parser_mod: parser_mod,
      parser_acc: parser_mod.init(),
      ready?: false,
      pending_persist?: false
    }

    {:ok, hydrate(state)}
  end

  @impl true
  def handle_cast({:feed, line}, state) do
    {result, new_acc} = state.parser_mod.feed(line, state.parser_acc)
    new_state = apply_parser_result(%{state | parser_acc: new_acc}, result)

    if changed?(state, new_state), do: broadcast(new_state)

    {:noreply, %{new_state | pending_persist?: true}}
  end

  def handle_cast(:reconcile, state) do
    # Skip when an enable/disable op is already in flight — its result will
    # land shortly and reflects newer intent than this probe.
    if state.compose_ref do
      {:noreply, state}
    else
      parent = self()
      name = state.name

      Task.start(fn -> send(parent, {:reconcile_done, probe_running(name)}) end)
      {:noreply, state}
    end
  end

  def handle_cast({:finish_update, opts}, state) do
    status = Keyword.get(opts, :status, "success")
    new_state = %{state | update_status: status}
    persist_user_field!(new_state, :last_update_status, status)
    broadcast(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, snapshot_struct(state), state}

  # Enable/disable reply immediately with an optimistic status and run the
  # `docker compose` op in a Task — an image pull can take minutes and must
  # never block this actor (or the LiveViews calling into it). The result
  # lands in `handle_info({:compose_done, ...})`.
  def handle_call(:enable, _from, state) do
    ref = start_compose_task(:start, state.name)

    new_state = %{
      state
      | enabled?: true,
        last_error: nil,
        status: derive_status(true, state.ready?, state.phase),
        compose_ref: ref
    }

    persist_user_fields!(new_state, %{enabled: true, last_error: nil})
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:disable, _from, state) do
    ref = start_compose_task(:stop, state.name)

    # Keep the observed status until the stop result arrives — the container
    # is still running right now.
    new_state = %{state | enabled?: false, last_error: nil, compose_ref: ref}

    persist_user_fields!(new_state, %{enabled: false, last_error: nil})
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:begin_update, _from, state) do
    new_state = %{state | update_status: "running"}
    persist_user_field!(new_state, :last_update_status, "running")
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:set_auto_update, enabled}, _from, state) do
    new_state = %{state | auto_update_enabled?: enabled}
    persist_user_field!(new_state, :auto_update_enabled, enabled)
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:compose_done, ref, op, result}, %{compose_ref: ref} = state) do
    new_state =
      case {op, result} do
        {:start, {:ok, _output}} ->
          # Container is up — attach a tailer so the parser keeps deriving
          # status/progress without anyone opening the logs viewer.
          safe_start_tail(state.name)
          state

        {:stop, {:ok, _output}} ->
          %{state | status: :stopped, last_error: nil}

        {:start, {:error, _code, output}} ->
          %{state | status: :error, last_error: trim_error(output)}

        {:stop, {:error, _code, output}} ->
          # The container may still be running — keep the observed status so
          # the UI doesn't claim "stopped" for a service that didn't stop.
          %{state | last_error: trim_error(output)}
      end

    new_state = %{new_state | compose_ref: nil}

    if changed?(state, new_state) do
      persist_user_fields!(new_state, %{last_error: new_state.last_error})
      broadcast(new_state)
    end

    {:noreply, new_state}
  end

  # A newer enable/disable superseded this op — drop the stale result.
  def handle_info({:compose_done, _stale_ref, _op, _result}, state), do: {:noreply, state}

  def handle_info({:reconcile_done, result}, state) do
    new_state =
      case {result, state.enabled?} do
        {{:ok, true}, _enabled} ->
          # Container runs — make sure the parser gets fed, and never show a
          # dead status for a live container.
          safe_start_tail(state.name)

          if state.status in [nil, :unknown, :stopped, :error] do
            %{state | status: :starting}
          else
            state
          end

        {{:ok, false}, true} ->
          # Desired up, actually down (compose down / redeploy) — heal.
          ref = start_compose_task(:start, state.name)
          %{state | status: :starting, last_error: nil, compose_ref: ref}

        {{:ok, false}, _enabled} ->
          if state.status in [:ready, :starting, :downloading, :building] do
            %{state | status: :stopped, ready?: false}
          else
            state
          end

        {{:error, _code, _output}, _enabled} ->
          # Probe failed (socket down etc.) — the preflight banner covers it.
          state
      end

    if changed?(state, new_state) do
      broadcast(new_state)
      {:noreply, %{new_state | pending_persist?: true}}
    else
      {:noreply, new_state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  ## Internals

  defp hydrate(state) do
    case Repo.get_by(Service, name: state.name) do
      nil ->
        state

      row ->
        hydrated = %{
          state
          | enabled?: row.enabled,
            status: row.status,
            phase: row.phase,
            progress: row.progress,
            last_log: row.last_log,
            disk_bytes: row.disk_bytes,
            last_seen_at: row.last_seen_at,
            auto_update_enabled?: row.auto_update_enabled,
            update_status: row.last_update_status,
            last_error: row.last_error
        }

        # Derive a baseline status whenever the DB row doesn't carry one
        # (fresh seed rows, or rows from before status was tracked).
        if is_nil(hydrated.status) do
          %{hydrated | status: derive_status(hydrated.enabled?, hydrated.ready?, hydrated.phase)}
        else
          hydrated
        end
    end
  end

  defp apply_parser_result(state, result) do
    next_phase = Map.get(result, :phase) || state.phase
    next_ready = Map.get(result, :ready, false) or state.ready?

    %{
      state
      | phase: next_phase,
        progress: Map.get(result, :progress) || state.progress,
        last_log: Map.get(result, :last_log_line) || state.last_log,
        ready?: next_ready,
        last_seen_at: DateTime.utc_now(),
        status: derive_status(state.enabled?, next_ready, next_phase)
    }
  end

  # Derive the user-visible status from (enabled?, ready?, phase). Mirrors
  # the SettingsPanel + ServiceCard badge palette so the UI can switch on
  # `:status` alone.
  defp derive_status(false, _ready, _phase), do: :stopped
  defp derive_status(true, true, _phase), do: :ready
  defp derive_status(true, _ready, phase) when phase in [:download, :downloading], do: :downloading
  defp derive_status(true, _ready, phase) when phase in [:build, :building, :compile], do: :building
  defp derive_status(true, _ready, phase) when phase in [:error, :unhealthy], do: phase
  defp derive_status(true, _ready, _phase), do: :starting

  defp snapshot_struct(state) do
    state
    |> Map.from_struct()
    |> Map.drop([:parser_mod, :parser_acc, :compose_ref])
  end

  defp changed?(s1, s2) do
    Map.drop(snapshot_struct(s1), [:last_seen_at]) !=
      Map.drop(snapshot_struct(s2), [:last_seen_at])
  end

  defp broadcast(state) do
    snap = snapshot_struct(state)
    PubSub.broadcast(Atlas.PubSub, "control:service:#{state.name}", {:service_update, snap})
    PubSub.broadcast(Atlas.PubSub, "control:status", :status_changed)
  end

  defp persist_user_field!(state, field, value),
    do: persist_user_fields!(state, %{field => value})

  defp persist_user_fields!(state, attrs) do
    case Repo.get_by(Service, name: state.name) do
      nil ->
        :ok

      row ->
        row
        |> Service.changeset(attrs)
        |> Repo.update!()
    end
  end

  # `docker compose` via the shared GenServer, run in a Task so this actor
  # stays responsive during long pulls; converted to an error tuple (instead
  # of crashing) when the compose process is down.
  defp start_compose_task(action, name) do
    ref = make_ref()
    parent = self()

    Task.start(fn ->
      send(parent, {:compose_done, ref, action, compose(action, name)})
    end)

    ref
  end

  defp compose(action, name) do
    case action do
      :start -> Atlas.Control.DockerCompose.start(name)
      :stop -> Atlas.Control.DockerCompose.stop(name)
    end
  rescue
    e -> {:error, 0, "control plane unavailable: #{Exception.message(e)}"}
  catch
    :exit, _reason -> {:error, 0, "control plane unavailable (docker compose is not running)"}
  end

  defp probe_running(name) do
    Atlas.Control.DockerCompose.running?(name)
  rescue
    e -> {:error, 0, Exception.message(e)}
  catch
    :exit, _reason -> {:error, 0, "docker compose is not running"}
  end

  # Feed the parser even when no logs viewer is open — status/progress
  # derivation depends on it. Best-effort: a missing tailer supervisor (test
  # env, broken CLI) must not take this actor down.
  defp safe_start_tail(name) do
    Atlas.Control.LogTailer.Supervisor.start_tail(name)
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp trim_error(output) when is_binary(output),
    do: output |> String.trim() |> String.slice(0, 2000)

  defp trim_error(other), do: other |> inspect() |> String.slice(0, 2000)
end
