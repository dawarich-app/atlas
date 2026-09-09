defmodule Atlas.Control do
  @moduledoc """
  Boundary for the control plane.

  Owns the self-hosted lifecycle: which region is selected, which sidecar
  services are running, and the download/convert/apply pipeline that turns a
  Geofabrik extract into data the map services can serve.
  """

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
      TransitSources,
      Onboarding,
      Service,
      ServiceCoverage,
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
      RegionCatalog,
      Jobs.AutoUpdateScan,
      Jobs.UpdateService
    ]
end
