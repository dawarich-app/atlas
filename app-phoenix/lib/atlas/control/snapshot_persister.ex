defmodule Atlas.Control.SnapshotPersister do
  @moduledoc """
  Periodic flush of `ServiceState` runtime fields to the `services` table.

  Hot-path fields (status, phase, progress, last_log, last_seen_at, disk_bytes)
  are held in the per-service GenServer for low-latency reads and broadcasts.
  Once every `@tick_ms` we walk `Seeder.known_services/0`, ask each ServiceState
  for a snapshot, and write the runtime columns back to Ecto with a single
  `update_all` per row.

  Tests don't want to wait five seconds for a tick. `flush_now/0` runs the
  same flush synchronously in the caller's process — useful from test setup
  or shutdown paths.
  """

  use GenServer

  import Ecto.Query

  alias Atlas.Repo
  alias Atlas.Control.{Seeder, Service, ServiceState}

  @tick_ms 5_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Run a flush synchronously in the current process. Used in tests and on
  graceful shutdown; production also runs this on every `@tick_ms` tick.
  """
  def flush_now do
    flush()
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    flush()
    schedule_tick()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    flush()
    :ok
  end

  defp flush do
    Enum.each(Seeder.known_services(), fn %{name: name} ->
      case safe_snapshot(name) do
        {:ok, snap} -> update_runtime_fields(name, snap)
        :error -> :ok
      end
    end)

    :ok
  end

  defp safe_snapshot(name) do
    {:ok, ServiceState.snapshot(name)}
  catch
    :exit, _ -> :error
  end

  defp update_runtime_fields(name, snap) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Service
    |> where([s], s.name == ^name)
    |> Repo.update_all(
      set: [
        status: snap.status || :unknown,
        phase: snap.phase,
        progress: snap.progress,
        last_log: snap.last_log,
        last_seen_at: snap.last_seen_at,
        disk_bytes: snap.disk_bytes || 0,
        updated_at: now
      ]
    )
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end
end
