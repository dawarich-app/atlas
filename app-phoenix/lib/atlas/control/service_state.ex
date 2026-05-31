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
    :pending_persist?
  ]

  ## Public API

  def start_link({name, profile, parser_mod}) do
    GenServer.start_link(__MODULE__, {name, profile, parser_mod}, name: Registry.via(name))
  end

  def feed(name, line), do: GenServer.cast(Registry.via(name), {:feed, line})
  def snapshot(name), do: GenServer.call(Registry.via(name), :snapshot)
  def enable(name), do: GenServer.call(Registry.via(name), :enable)
  def disable(name), do: GenServer.call(Registry.via(name), :disable)
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

  def handle_cast({:finish_update, opts}, state) do
    status = Keyword.get(opts, :status, "success")
    new_state = %{state | update_status: status}
    persist_user_field!(new_state, :last_update_status, status)
    broadcast(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, snapshot_struct(state), state}

  def handle_call(:enable, _from, state) do
    _ = Atlas.Control.DockerCompose.start(state.name)
    new_state = %{state | enabled?: true, status: derive_status(true, state.ready?, state.phase)}
    persist_user_field!(new_state, :enabled, true)
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:disable, _from, state) do
    _ = Atlas.Control.DockerCompose.stop(state.name)
    new_state = %{state | enabled?: false, status: :stopped}
    persist_user_field!(new_state, :enabled, false)
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
            update_status: row.last_update_status
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
    |> Map.drop([:parser_mod, :parser_acc])
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

  defp persist_user_field!(state, field, value) do
    case Repo.get_by(Service, name: state.name) do
      nil ->
        :ok

      row ->
        row
        |> Service.changeset(%{field => value})
        |> Repo.update!()
    end
  end
end
