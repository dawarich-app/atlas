defmodule AtlasWeb.Api.V1.CoverageController do
  @moduledoc """
  `GET /api/v1/coverage` — service readiness and installed regional coverage
  for each public maps capability.
  """

  use AtlasWeb.Api.V1.BaseController

  alias Atlas.Control.ServiceCoverage
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [response: 3]

  operation(:show,
    summary: "List available regions for each maps capability",
    description: """
    Combines live service health with provenance from the datasets installed on
    this Atlas instance. `regions` contains only region names Atlas can verify;
    an empty list with `coverage_status=unknown` does not prove that the service
    has no coverage. Map matching inherits routing's Valhalla coverage. Transit
    timetable coverage is reported separately in `transit_feeds` because it can
    differ from the walking-network regions.
    """,
    responses: %{
      200 => response("Capability coverage", "application/json", Schemas.CoverageResponse)
    }
  )

  def show(conn, _params) do
    json(conn, %{data: ServiceCoverage.summary(), meta: meta(conn)})
  end
end
