defmodule AtlasWeb.Api.V1.GeocodeController do
  use AtlasWeb.Api.V1.BaseController
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
      400 => response("Missing parameter", "application/json", Schemas.Error)
    }
  )

  def index(conn, params) do
    case require_param(conn, "q") do
      {:ok, q} ->
        result = Geocode.lookup(query: String.trim(q), lang: params["lang"])

        json(conn, %{
          data: result.features,
          meta: meta(conn, %{upstream: result.upstream_status})
        })

      {:error, :missing} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "MISSING_PARAM", param: "q"}})
    end
  end
end
