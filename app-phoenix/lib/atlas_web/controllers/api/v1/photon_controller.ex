defmodule AtlasWeb.Api.V1.PhotonController do
  use AtlasWeb.Api.V1.BaseController

  alias Atlas.Maps.Upstream.PhotonPassthrough

  import OpenApiSpex.Operation, only: [response: 3]

  @raw_schema %OpenApiSpex.Schema{
    type: :object,
    description:
      "Photon response, passed through unmodified (GeoJSON FeatureCollection for api/reverse/lookup)"
  }

  operation(:search,
    summary: "Raw Photon forward-geocode passthrough (Photon /api)",
    responses: %{200 => response("Photon GeoJSON", "application/json", @raw_schema)}
  )

  def search(conn, _params), do: passthrough(conn, :search)

  operation(:reverse,
    summary: "Raw Photon reverse-geocode passthrough (Photon /reverse)",
    responses: %{200 => response("Photon GeoJSON", "application/json", @raw_schema)}
  )

  def reverse(conn, _params), do: passthrough(conn, :reverse)

  operation(:lookup,
    summary: "Raw Photon lookup-by-osm-id passthrough (Photon /lookup)",
    responses: %{200 => response("Photon GeoJSON", "application/json", @raw_schema)}
  )

  def lookup(conn, _params), do: passthrough(conn, :lookup)

  operation(:status,
    summary: "Raw Photon status passthrough (Photon /status)",
    responses: %{200 => response("Photon status", "application/json", @raw_schema)}
  )

  def status(conn, _params), do: passthrough(conn, :status)

  defp passthrough(conn, action) do
    case PhotonPassthrough.forward(action, conn.query_string) do
      {:ok, %{status: status, body: body}} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(status, body)

      {:error, exception} ->
        error(conn, :service_unavailable, "UPSTREAM_UNAVAILABLE", Exception.message(exception))
    end
  end
end
