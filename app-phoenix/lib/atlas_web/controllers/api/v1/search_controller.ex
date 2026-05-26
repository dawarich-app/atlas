defmodule AtlasWeb.Api.V1.SearchController do
  use AtlasWeb.Api.V1.BaseController
  alias Atlas.Maps.Search

  def index(conn, params) do
    case require_param(conn, "q") do
      {:error, :missing} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "MISSING_PARAM", param: "q", message: "param q is required"}})

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
