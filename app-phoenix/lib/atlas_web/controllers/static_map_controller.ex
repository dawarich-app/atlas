defmodule AtlasWeb.StaticMapController do
  use AtlasWeb, :controller

  alias Atlas.Geometry.Polyline
  alias Atlas.Settings

  plug :put_layout, html: {AtlasWeb.Layouts, :static}

  def show(conn, params) do
    route_param = params["route"] || ""

    assigns = %{
      tiles_url: Settings.get("tiles_url") || System.get_env("TILES_URL") || "",
      theme:
        params["theme"] ||
          Settings.get("tiles_theme") ||
          System.get_env("TILES_THEME") ||
          "atlas-light",
      lat: float_or(params["lat"], 51.1657),
      lon: float_or(params["lon"], 10.4515),
      zoom: float_or(params["zoom"], 5.0),
      width: clamp_int(params["width"], 64, 4096, 800),
      height: clamp_int(params["height"], 64, 4096, 600),
      route: route_param,
      route_geojson: route_geojson(route_param),
      title: params["title"] || "",
      subtitle: params["subtitle"] || "",
      brand: params["brand"] || "Dawarich Atlas",
      fit: params["fit"] == "1"
    }

    render(conn, :show, assigns)
  end

  defp route_geojson(""), do: ""
  defp route_geojson(nil), do: ""

  defp route_geojson(encoded) when is_binary(encoded) do
    coords =
      encoded
      |> Polyline.decode(6)
      |> Enum.map(fn {lat, lon} -> [lon, lat] end)

    if coords == [] do
      ""
    else
      Jason.encode!(%{
        type: "FeatureCollection",
        features: [
          %{
            type: "Feature",
            geometry: %{type: "LineString", coordinates: coords},
            properties: %{}
          }
        ]
      })
    end
  end

  defp float_or(nil, fallback), do: fallback

  defp float_or(str, fallback) when is_binary(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> fallback
    end
  end

  defp clamp_int(nil, _min, _max, fallback), do: fallback

  defp clamp_int(str, min_v, max_v, fallback) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n |> max(min_v) |> min(max_v)
      :error -> fallback
    end
  end
end
