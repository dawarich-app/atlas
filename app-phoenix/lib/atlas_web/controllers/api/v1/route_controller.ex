defmodule AtlasWeb.Api.V1.RouteController do
  use AtlasWeb.Api.V1.BaseController
  alias Atlas.Maps.Route

  def show(conn, params) do
    with {:ok, from} <- parse_latlon(params["from"]),
         {:ok, to} <- parse_latlon(params["to"]) do
      result =
        Route.plan(
          from: from,
          to: to,
          mode: params["mode"] || "auto",
          options: options(params)
        )

      json(conn, %{
        data: result.features,
        meta: meta(conn, %{upstream: result.upstream_status})
      })
    else
      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "MISSING_PARAM", message: "from and to required as 'lat,lon'"}})
    end
  end

  defp options(params) do
    %{}
    |> add_if(params["avoid_tolls"] in ["1", "true"], :avoid_tolls, true)
    |> add_if(params["avoid_highways"] in ["1", "true"], :avoid_highways, true)
    |> add_if(params["avoid_ferries"] in ["1", "true"], :avoid_ferries, true)
  end

  defp add_if(map, false, _key, _val), do: map
  defp add_if(map, true, key, val), do: Map.put(map, key, val)
end
