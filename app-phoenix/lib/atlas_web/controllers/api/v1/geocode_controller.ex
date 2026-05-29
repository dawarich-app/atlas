defmodule AtlasWeb.Api.V1.GeocodeController do
  use AtlasWeb.Api.V1.BaseController
  action_fallback AtlasWeb.Api.V1.FallbackController

  alias Atlas.Maps.Geocode
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [parameter: 5, response: 3]

  operation(:index,
    summary: "Geocode a free-text query (forward) or coordinate pair (reverse)",
    parameters: [
      parameter(:q, :query, :string, "Free-text query (forward mode)", required: false),
      parameter(:lat, :query, :number, "Latitude (reverse mode)", required: false),
      parameter(:lon, :query, :number, "Longitude (reverse mode)", required: false),
      parameter(:limit, :query, :integer, "Max forward results (1-25)", required: false),
      parameter(:lang, :query, :string, "Language code", required: false)
    ],
    responses: %{
      200 => response("Geocode result", "application/json", Schemas.Response),
      400 => response("Missing parameter", "application/json", Schemas.Error),
      422 => response("Invalid parameter", "application/json", Schemas.Error),
      502 => response("Upstream error", "application/json", Schemas.Error),
      503 => response("Upstream unavailable", "application/json", Schemas.Error)
    }
  )

  def index(conn, params) do
    q = params["q"]
    lat = parse_float(params["lat"])
    lon = parse_float(params["lon"])
    limit = clamp_int(params["limit"], 8, 1, 25)

    case Geocode.lookup(query: q, lat: lat, lon: lon, lang: params["lang"], limit: limit) do
      {:ok, :forward, result} ->
        json(conn, %{
          data: result.features,
          meta:
            meta(conn, %{
              mode: "forward",
              upstream: result.upstream_status,
              count: length(result.features)
            })
        })

      {:ok, :reverse, result} ->
        json(conn, %{
          data: result.features,
          meta: meta(conn, %{mode: "reverse", upstream: result.upstream_status})
        })

      {:error, :missing, _} = err ->
        err

      {:error, _} = err ->
        err
    end
  end
end
