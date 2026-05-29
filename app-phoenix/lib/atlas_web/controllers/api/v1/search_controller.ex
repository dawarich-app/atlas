defmodule AtlasWeb.Api.V1.SearchController do
  use AtlasWeb.Api.V1.BaseController
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
      400 => response("Missing parameter", "application/json", Schemas.Error)
    }
  )

  def index(conn, params) do
    case require_param(conn, "q") do
      {:error, :missing} ->
        missing_param(conn, "q")

      {:ok, q} ->
        opts = %{
          query: String.trim(q),
          limit: clamp_int(params["limit"], 25, 1, 50),
          lang: params["lang"],
          lat: parse_float(params["lat"]),
          lon: parse_float(params["lon"]),
          bbox: parse_bbox(params["bbox"])
        }

        result = Search.autocomplete(opts)

        json(conn, %{
          data: result.features,
          meta:
            meta(conn, %{upstream: result.upstream_status, count: length(result.features)})
        })
    end
  end
end
