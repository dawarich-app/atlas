defmodule AtlasWeb.MapContext do
  @moduledoc "A small, validated per-browser-tab map draft. Never stores service settings."
  alias Atlas.Maps.Discovery
  alias AtlasWeb.RouteEndpoint

  def dump(a) do
    %{
      query: a.search_query,
      categories: a.categories,
      scope: a.search_scope,
      bbox: a.search_bbox,
      city: a.search_city,
      viewport: a.viewport,
      tab: if(a.active_tab == "settings", do: a.last_map_tab, else: a.active_tab),
      mode: a.mode,
      options: a.route_options,
      departure: a.route_departure,
      endpoints:
        Map.new(a.route_endpoints, fn {key, e} ->
          {key, %{query: e.query, coords: e.coords}}
        end)
    }
  end

  def restore(data) when is_map(data) do
    %{
      active_tab: if(data["tab"] == "route", do: "route", else: "search"),
      last_map_tab: if(data["tab"] == "route", do: "route", else: "search"),
      mode:
        if(data["mode"] in ~w(auto bicycle pedestrian transit), do: data["mode"], else: "auto"),
      route_endpoints: Map.new(~w(from to), &{&1, endpoint(nested(data, "endpoints", &1))}),
      route_options:
        Map.new(
          ~w(avoid_tolls avoid_highways avoid_ferries),
          &{&1, nested(data, "options", &1) == true}
        ),
      search_query: text(data["query"]),
      search_city: text(data["city"]),
      categories:
        Discovery.category_ids(
          Enum.join(List.wrap(data["categories"]) |> Enum.filter(&is_binary/1), ",")
        ),
      search_scope: if(data["scope"] == "area", do: "area", else: "all"),
      search_bbox: bbox(data["bbox"]),
      viewport: bbox(data["viewport"]),
      route_departure: text(data["departure"])
    }
  end

  def restore(_), do: restore(%{})

  defp nested(data, field, key) do
    case data[field] do
      value when is_map(value) -> value[key]
      _ -> nil
    end
  end

  defp endpoint(%{"query" => query, "coords" => %{"lat" => lat, "lon" => lon}})
       when is_number(lat) and is_number(lon) and lat >= -90 and lat <= 90 and lon >= -180 and
              lon <= 180 do
    RouteEndpoint.select(%{label: text(query), coords: %{lat: lat, lon: lon}})
  end

  defp endpoint(%{"query" => query}), do: RouteEndpoint.new(text(query))
  defp endpoint(_), do: RouteEndpoint.new()
  defp text(value) when is_binary(value), do: String.slice(value, 0, 500)
  defp text(_), do: ""

  defp bbox([w, s, e, n]) when is_number(w) and is_number(s) and is_number(e) and is_number(n),
    do: Discovery.bbox(Enum.join([w, s, e, n], ","))

  defp bbox(_), do: nil
end
