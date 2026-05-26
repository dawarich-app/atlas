defmodule AtlasWeb.Api.V1.ReverseController do
  use AtlasWeb.Api.V1.BaseController
  alias Atlas.Maps.Reverse

  def show(conn, params) do
    with {:ok, lat_raw} <- require_param(conn, "lat"),
         {:ok, lon_raw} <- require_param(conn, "lon"),
         lat when not is_nil(lat) <- parse_float(lat_raw),
         lon when not is_nil(lon) <- parse_float(lon_raw) do
      result = Reverse.lookup(lat: lat, lon: lon, lang: params["lang"])

      json(conn, %{
        data: result.features,
        meta: meta(conn, %{upstream: result.upstream_status})
      })
    else
      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "MISSING_PARAM", message: "lat and lon required"}})
    end
  end

  def batch(conn, %{"coords" => coords} = params) when is_list(coords) do
    normalized =
      Enum.map(coords, fn
        %{"lat" => lat, "lon" => lon} -> %{lat: lat * 1.0, lon: lon * 1.0}
      end)

    result = Reverse.batch(%{coords: normalized, lang: params["lang"]})

    json(conn, %{
      data: result.results,
      meta:
        meta(conn, %{
          count: length(result.results),
          cache_hits: result.cache_hits,
          cache_misses: result.cache_misses,
          upstream_errors: result.upstream_errors,
          grid_precision: Reverse.grid_decimals(),
          max_coords: Reverse.max_coords()
        })
    })
  end

  def batch(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "MISSING_PARAM", param: "coords", message: "coords array required"}})
  end
end
