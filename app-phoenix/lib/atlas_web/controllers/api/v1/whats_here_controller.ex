defmodule AtlasWeb.Api.V1.WhatsHereController do
  use AtlasWeb.Api.V1.BaseController
  alias Atlas.Maps.WhatsHere

  def index(conn, params) do
    with lat when not is_nil(lat) <- parse_float(params["lat"]),
         lon when not is_nil(lon) <- parse_float(params["lon"]) do
      radius = clamp_int(params["radius"], 200, 10, 2000)
      result = WhatsHere.lookup(lat: lat, lon: lon, radius: radius, lang: params["lang"])

      json(conn, %{
        data: result.features,
        meta: meta(conn, %{radius: radius, upstream: result.upstream_status})
      })
    else
      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "MISSING_PARAM", message: "lat and lon required"}})
    end
  end
end
