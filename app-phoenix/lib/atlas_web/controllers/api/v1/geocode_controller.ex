defmodule AtlasWeb.Api.V1.GeocodeController do
  use AtlasWeb.Api.V1.BaseController
  action_fallback AtlasWeb.Api.V1.FallbackController

  alias Atlas.Maps.Geocode
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [parameter: 5, response: 3]

  operation(:index,
    summary: "Geocode a free-text query",
    parameters: [
      parameter(:q, :query, :string, "Free-text query", required: true),
      parameter(:lang, :query, :string, "Language code", required: false)
    ],
    responses: %{
      200 => response("Geocode result", "application/json", Schemas.Response),
      400 => response("Missing parameter", "application/json", Schemas.Error),
      502 => response("Upstream error", "application/json", Schemas.Error),
      503 => response("Upstream unavailable", "application/json", Schemas.Error)
    }
  )

  def index(conn, params) do
    with {:ok, q} <- require_q(params),
         {:ok, result} <- Geocode.lookup(query: String.trim(q), lang: params["lang"]) do
      json(conn, %{
        data: result.features,
        meta: meta(conn, %{upstream: result.upstream_status})
      })
    end
  end

  defp require_q(params) do
    case params["q"] do
      nil -> {:error, :missing, "q"}
      "" -> {:error, :missing, "q"}
      v -> {:ok, v}
    end
  end
end
