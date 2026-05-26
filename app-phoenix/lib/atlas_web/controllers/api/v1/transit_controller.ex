defmodule AtlasWeb.Api.V1.TransitController do
  use AtlasWeb.Api.V1.BaseController
  alias Atlas.Maps.Transit

  def show(conn, params) do
    with {:ok, from} <- parse_latlon(params["from"]),
         {:ok, to} <- parse_latlon(params["to"]) do
      result =
        Transit.plan(
          from: from,
          to: to,
          date: params["date"],
          time: params["time"],
          arrive_by: params["arrive_by"]
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
end
