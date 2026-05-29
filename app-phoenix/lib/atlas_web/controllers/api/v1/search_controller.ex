defmodule AtlasWeb.Api.V1.SearchController do
  use AtlasWeb.Api.V1.BaseController
  action_fallback AtlasWeb.Api.V1.FallbackController

  alias Atlas.Maps.Search
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [parameter: 5, response: 3]

  operation(:index,
    summary: "Search for places",
    parameters: [
      parameter(:q, :query, :string, "Free-text query", required: true),
      parameter(:limit, :query, :integer, "Max results (1-50)", required: false),
      parameter(:lang, :query, :string, "Language code", required: false),
      parameter(:lat, :query, :number, "Bias latitude", required: false),
      parameter(:lon, :query, :number, "Bias longitude", required: false),
      parameter(:bbox, :query, :string, "BBox 'w,s,e,n'", required: false)
    ],
    responses: %{
      200 => response("Search results", "application/json", Schemas.Response),
      400 => response("Missing parameter", "application/json", Schemas.Error),
      502 => response("Upstream error", "application/json", Schemas.Error),
      503 => response("Upstream unavailable", "application/json", Schemas.Error)
    }
  )

  def index(conn, params) do
    with {:ok, q} <- require_q(conn, params),
         {:ok, result} <- Search.autocomplete(opts_from(params, q)) do
      json(conn, %{
        data: result.features,
        meta: meta(conn, %{upstream: result.upstream_status, count: length(result.features)})
      })
    end
  end

  defp require_q(_conn, params) do
    case params["q"] do
      nil -> {:error, :missing, "q"}
      "" -> {:error, :missing, "q"}
      v -> {:ok, v}
    end
  end

  defp opts_from(params, q) do
    %{
      query: String.trim(q),
      limit: clamp_int(params["limit"], 25, 1, 50),
      lang: params["lang"],
      lat: parse_float(params["lat"]),
      lon: parse_float(params["lon"]),
      bbox: parse_bbox(params["bbox"])
    }
  end
end
