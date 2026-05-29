defmodule AtlasWeb.Api.V1.RouteController do
  use AtlasWeb.Api.V1.BaseController
  action_fallback AtlasWeb.Api.V1.FallbackController

  alias Atlas.Maps.Route
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [parameter: 5, response: 3]

  operation(:show,
    summary: "Plan a route between two coordinates",
    parameters: [
      parameter(:from, :query, :string, "Origin 'lat,lon'", required: true),
      parameter(:to, :query, :string, "Destination 'lat,lon'", required: true),
      parameter(:mode, :query, :string, "Travel mode (auto, bicycle, pedestrian)", required: false),
      parameter(:avoid_tolls, :query, :string, "Avoid tolls", required: false),
      parameter(:avoid_highways, :query, :string, "Avoid highways", required: false),
      parameter(:avoid_ferries, :query, :string, "Avoid ferries", required: false)
    ],
    responses: %{
      200 => response("Route result", "application/json", Schemas.Response),
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
           Route.plan(
             from: from,
             to: to,
             mode: params["mode"] || "auto",
             options: options(params)
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

  defp options(params) do
    %{}
    |> add_if(params["avoid_tolls"] in ["1", "true"], :avoid_tolls, true)
    |> add_if(params["avoid_highways"] in ["1", "true"], :avoid_highways, true)
    |> add_if(params["avoid_ferries"] in ["1", "true"], :avoid_ferries, true)
  end

  defp add_if(map, false, _key, _val), do: map
  defp add_if(map, true, key, val), do: Map.put(map, key, val)
end
