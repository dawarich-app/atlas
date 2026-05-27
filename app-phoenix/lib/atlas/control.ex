defmodule Atlas.Control do
  use Boundary,
    deps: [
      Atlas.Repo,
      Atlas.Settings,
      Atlas.PubSub,
      Phoenix.PubSub,
      Crontab,
      Oban,
      Ecto,
      Ecto.Query
    ],
    exports: [
      Service,
      RegionSelection,
      Parser,
      Registry,
      DockerCompose,
      Osmium,
      Seeder,
      ServiceState,
      ServiceSupervisor,
      LogTailer,
      SnapshotPersister,
      TilesDownloader,
      RegionApplier,
      Jobs.AutoUpdateScan,
      Jobs.UpdateService
    ]
end
