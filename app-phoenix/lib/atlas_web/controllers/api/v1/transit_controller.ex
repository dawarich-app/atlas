defmodule AtlasWeb.Api.V1.TransitController do
  use AtlasWeb.Api.V1.BaseController
  action_fallback AtlasWeb.Api.V1.FallbackController

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
      400 => response("Missing parameter", "application/json", Schemas.Error),
      422 => response("Invalid parameter", "application/json", Schemas.Error),
      502 => response("Upstream error", "application/json", Schemas.Error),
      503 => response("Upstream unavailable", "application/json", Schemas.Error)
    }
  )

  def show(conn, params) do
    with {:ok, from} <- parse_endpoint(params["from"], "from"),
         {:ok, to} <- parse_endpoint(params["to"], "to"),
         {:ok, result} <-
           Transit.plan(
             from: from,
             to: to,
             date: params["date"],
             time: params["time"],
             arrive_by: params["arrive_by"]
           ) do
      json(conn, %{
        data: result.features,
        meta: meta(conn, %{upstream: result.upstream_status})
      })
    end
  end

  defp parse_endpoint(nil, name), do: {:error, :missing, name}
  defp parse_endpoint("", name), do: {:error, :missing, name}

  defp parse_endpoint(raw, name) do
    case parse_latlon(raw) do
      {:ok, coord} -> {:ok, coord}
      :error -> {:error, :invalid, "#{name} must be 'lat,lon'", %{param: name}}
    end
  end
end
