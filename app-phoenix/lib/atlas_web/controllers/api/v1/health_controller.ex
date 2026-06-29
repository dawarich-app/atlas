defmodule AtlasWeb.Api.V1.HealthController do
  use AtlasWeb.Api.V1.BaseController
  alias Atlas.Control.Health
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [response: 3]

  operation(:show,
    summary: "Per-capability health of the maps API",
    responses: %{200 => response("Health", "application/json", Schemas.Response)}
  )

  def show(conn, _params) do
    json(conn, %{data: Health.summary(), meta: meta(conn)})
  end
end
