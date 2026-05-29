defmodule AtlasWeb.Api.V1.TransitController do
  use AtlasWeb.Api.V1.BaseController
  alias Atlas.Maps.Transit
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [parameter: 5, response: 3]

  operation(:show,
    summary: "Plan a transit trip between two coordinates",
    parameters: [
      parameter(:from, :query, :string, "Origin 'lat,lon'", required: true),
      parameter(:to, :query, :string, "Destination 'lat,lon'", required: true),
      parameter(:date, :query, :string, "Date (YYYY-MM-DD)", required: false),
      parameter(:time, :query, :string, "Time (HH:MM)", required: false),
      parameter(:arrive_by, :query, :string, "Arrive-by flag", required: false)
    ],
    responses: %{
      200 => response("Transit result", "application/json", Schemas.Response),
      400 => response("Missing parameter", "application/json", Schemas.Error)
    }
  )

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
