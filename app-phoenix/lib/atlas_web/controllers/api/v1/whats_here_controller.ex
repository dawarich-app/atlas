defmodule AtlasWeb.Api.V1.WhatsHereController do
  use AtlasWeb.Api.V1.BaseController
  action_fallback AtlasWeb.Api.V1.FallbackController

  alias Atlas.Maps.WhatsHere
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [parameter: 5, response: 3]

  operation(:index,
    summary: "Describe what is at a coordinate (reverse + nearby fan-out)",
    parameters: [
      parameter(:lat, :query, :number, "Latitude", required: true),
      parameter(:lon, :query, :number, "Longitude", required: true),
      parameter(:radius, :query, :integer, "Search radius in meters (10-2000)", required: false),
      parameter(:lang, :query, :string, "Language code", required: false)
    ],
    responses: %{
      200 => response("WhatsHere result", "application/json", Schemas.Response),
      400 => response("Missing parameter", "application/json", Schemas.Error),
      422 => response("Invalid parameter", "application/json", Schemas.Error),
      502 => response("Upstream error", "application/json", Schemas.Error),
      503 => response("Upstream unavailable", "application/json", Schemas.Error)
    }
  )

  def index(conn, %{"lat" => lat_raw, "lon" => lon_raw} = params)
      when is_binary(lat_raw) and is_binary(lon_raw) do
    with {:ok, lat} <- parse_float_or_invalid(lat_raw, "lat"),
         {:ok, lon} <- parse_float_or_invalid(lon_raw, "lon") do
      radius = clamp_int(params["radius"], 200, 10, 2000)

      with {:ok, result} <-
             WhatsHere.lookup(lat: lat, lon: lon, radius: radius, lang: params["lang"]) do
        json(conn, %{
          data: result.features,
          meta: meta(conn, %{radius: radius, upstream: result.upstream_status})
        })
      end
    end
  end

  def index(_conn, _params), do: {:error, :missing, "lat or lon"}

  defp parse_float_or_invalid(raw, name) do
    case parse_float(raw) do
      nil -> {:error, :invalid, "#{name} must be numeric", %{param: name}}
      f -> {:ok, f}
    end
  end
end
