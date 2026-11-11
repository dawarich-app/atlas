defmodule AtlasWeb.Api.V1.ValhallaController do
  use AtlasWeb.Api.V1.BaseController

  alias Atlas.Maps.Upstream.ValhallaPassthrough
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [parameter: 5, response: 3]

  @raw_schema %OpenApiSpex.Schema{
    type: :object,
    description: "Valhalla response, passed through unmodified (status and body)"
  }

  operation(:route,
    summary: "Raw Valhalla route passthrough (Valhalla /route)",
    parameters: [
      parameter(
        :json,
        :query,
        :string,
        "A Valhalla /route request as JSON, exactly as Valhalla takes it",
        required: true
      )
    ],
    responses: %{
      200 => response("Valhalla route", "application/json", @raw_schema),
      400 => response("Valhalla's own error", "application/json", @raw_schema),
      503 => response("Valhalla unreachable", "application/json", Schemas.Error)
    }
  )

  def route(conn, _params) do
    case ValhallaPassthrough.forward(:route, conn.query_string) do
      {:ok, %{status: status, body: body}} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(status, body)

      {:error, exception} ->
        error(conn, :service_unavailable, "UPSTREAM_UNAVAILABLE", Exception.message(exception))
    end
  end
end
