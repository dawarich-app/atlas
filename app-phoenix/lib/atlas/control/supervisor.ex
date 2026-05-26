defmodule Atlas.Control.Supervisor do
  @moduledoc """
  Top-level supervisor for the `Atlas.Control` sub-tree.

  Children are started with `:rest_for_one`: if `DockerCompose` crashes, every
  process below it (which trusts its API) is restarted in declaration order.

  `post_start/0` is called by `Atlas.Application` after `Supervisor.start_link/2`
  returns. It seeds the `services` table and spawns a `ServiceState` per known
  upstream service.
  """

  use Supervisor

  alias Atlas.Control.{
    DockerCompose,
    LogTailer,
    Osmium,
    RegionApplier,
    Seeder,
    ServiceSupervisor,
    SnapshotPersister,
    TilesDownloader
  }

  def start_link(_), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    children = [
      {Registry, keys: :unique, name: Atlas.Control.Registry},
      DockerCompose,
      Osmium,
      ServiceSupervisor,
      LogTailer.Supervisor,
      TilesDownloader,
      RegionApplier,
      SnapshotPersister
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc "Called after supervision is up. Seeds DB rows + starts a ServiceState per known service."
  def post_start, do: Seeder.seed_and_start!()
end
