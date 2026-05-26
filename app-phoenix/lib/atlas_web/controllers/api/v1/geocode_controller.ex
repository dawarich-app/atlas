defmodule AtlasWeb.Api.V1.GeocodeController do
  use AtlasWeb.Api.V1.BaseController
  alias Atlas.Maps.Geocode

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
