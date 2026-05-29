defmodule AtlasWeb.Api.V1.ReverseController do
  use AtlasWeb.Api.V1.BaseController
  action_fallback AtlasWeb.Api.V1.FallbackController

  alias Atlas.Maps.Reverse
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [parameter: 5, response: 3]

  operation(:show,
    summary: "Reverse-geocode a single coordinate",
    parameters: [
      parameter(:lat, :query, :number, "Latitude", required: true),
      parameter(:lon, :query, :number, "Longitude", required: true),
      parameter(:lang, :query, :string, "Language code", required: false)
    ],
    responses: %{
      200 => response("Reverse result", "application/json", Schemas.Response),
      400 => response("Missing parameter", "application/json", Schemas.Error),
      422 => response("Invalid parameter", "application/json", Schemas.Error),
      502 => response("Upstream error", "application/json", Schemas.Error),
      503 => response("Upstream unavailable", "application/json", Schemas.Error)
    }
  )

  def show(conn, %{"lat" => lat_raw, "lon" => lon_raw} = params)
      when is_binary(lat_raw) and is_binary(lon_raw) do
    with {:ok, lat} <- parse_float_or_invalid(lat_raw, "lat"),
         {:ok, lon} <- parse_float_or_invalid(lon_raw, "lon"),
         {:ok, result} <- Reverse.lookup(lat: lat, lon: lon, lang: params["lang"]) do
      json(conn, %{
        data: result.features,
        meta: meta(conn, %{upstream: result.upstream_status})
      })
    end
  end

  def show(_conn, _params), do: {:error, :missing, "lat or lon"}

  operation(:batch,
    summary: "Reverse-geocode a batch of coordinates",
    request_body:
      {"Batch request", "application/json",
       %OpenApiSpex.Schema{type: :object, properties: %{coords: %OpenApiSpex.Schema{type: :array}}}},
    responses: %{
      200 => response("Batch reverse results", "application/json", Schemas.Response),
      400 => response("Missing coords", "application/json", Schemas.Error),
      422 => response("Invalid coord", "application/json", Schemas.Error)
    }
  )

  def batch(conn, %{"coords" => coords} = params) when is_list(coords) do
    with {:ok, summary} <- Reverse.batch(%{coords: coords, lang: params["lang"]}) do
      json(conn, %{
        data: summary.results,
        meta:
          meta(conn, %{
            count: length(summary.results),
            cache_hits: summary.cache_hits,
            cache_misses: summary.cache_misses,
            upstream_errors: summary.upstream_errors,
            grid_precision: Reverse.grid_decimals(),
            max_coords: Reverse.max_coords()
          })
      })
    end
  end

  def batch(_conn, _params), do: {:error, :missing, "coords"}

  defp parse_float_or_invalid(raw, name) do
    case parse_float(raw) do
      nil -> {:error, :invalid, "#{name} must be numeric", %{param: name}}
      f -> {:ok, f}
    end
  end
end
