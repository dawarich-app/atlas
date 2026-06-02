defmodule AtlasWeb.Api.V1.RouteController do
  use AtlasWeb.Api.V1.BaseController
  action_fallback AtlasWeb.Api.V1.FallbackController

  alias Atlas.Maps.Route
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [parameter: 5, response: 3]

  @valid_modes ~w(auto bicycle pedestrian motorcycle bus truck)

  operation(:show,
    summary: "Plan a route between two coordinates",
    parameters: [
      parameter(:from, :query, :string, "Origin 'lat,lon'", required: true),
      parameter(:to, :query, :string, "Destination 'lat,lon'", required: true),
      parameter(:mode, :query, :string, "Travel mode (auto, bicycle, pedestrian)",
        required: false
      ),
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
         {:ok, mode} <- parse_mode(params["mode"]),
         opts = options(params),
         {:ok, result} <-
           Route.plan(
             from: from,
             to: to,
             mode: mode,
             options: opts
           ) do
      json(conn, %{
        data: result.features,
        meta: meta(conn, %{mode: mode, options: opts})
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

  defp parse_mode(nil), do: {:ok, "auto"}
  defp parse_mode(""), do: {:ok, "auto"}

  defp parse_mode(m) when is_binary(m) do
    if m in @valid_modes do
      {:ok, m}
    else
      {:error, :invalid, "mode must be one of #{Enum.join(@valid_modes, ", ")}",
       %{param: "mode", allowed: @valid_modes}}
    end
  end

  defp options(params) do
    %{
      avoid_tolls: truthy?(params["avoid_tolls"]),
      avoid_highways: truthy?(params["avoid_highways"]),
      avoid_ferries: truthy?(params["avoid_ferries"])
    }
  end

  defp truthy?(v) when v in ["1", "true", "TRUE", "True", "yes", "on", true], do: true
  defp truthy?(_), do: false
end
