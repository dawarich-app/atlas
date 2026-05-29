defmodule AtlasWeb.MapLive do
  use AtlasWeb, :live_view

  alias Atlas.Maps
  alias Atlas.Settings
  alias Atlas.Control.{Seeder, ServiceState}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Atlas.PubSub, "control:status")
    end

    tiles_url =
      Settings.get("tiles_url") || System.get_env("TILES_URL") || ""

    theme =
      Settings.get("tiles_theme") || System.get_env("TILES_THEME") || "atlas-light"

    {:ok,
     assign(socket,
       page_title: "Atlas",
       tiles_url: tiles_url,
       theme: theme,
       search_query: "",
       search_results: [],
       directions: nil,
       mode: "auto",
       places: [],
       service_status: %{},
       upstream_status: "ok"
     )}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    trimmed = String.trim(q)

    if trimmed == "" do
      {:noreply, assign(socket, search_query: q, search_results: [])}
    else
      case Maps.Search.autocomplete(%{
             query: trimmed,
             limit: 8,
             lang: nil,
             lat: nil,
             lon: nil,
             bbox: nil
           }) do
        {:ok, result} ->
          {:noreply,
           socket
           |> assign(
             search_query: q,
             search_results: result.features,
             upstream_status: result.upstream_status
           )
           |> push_event("map:clear_markers", %{})}

        {:error, _e} ->
          {:noreply,
           socket
           |> assign(
             search_query: q,
             search_results: [],
             upstream_status: "unavailable"
           )
           |> push_event("map:clear_markers", %{})}
      end
    end
  end

  @impl true
  def handle_event("select_result", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.search_results, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      feature ->
        coords = feature.coords

        {:noreply,
         socket
         |> push_event("map:fly_to", %{lat: coords.lat, lon: coords.lon, zoom: 14})
         |> push_event("map:add_marker", %{
           id: feature.id,
           lat: coords.lat,
           lon: coords.lon,
           label: feature.label
         })}
    end
  end

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, mode: mode)}
  end

  @impl true
  def handle_event("route", %{"from" => from, "to" => to} = params, socket) do
    mode = Map.get(params, "mode", socket.assigns.mode)

    with {:ok, from_coords} <- parse_latlon(from),
         {:ok, to_coords} <- parse_latlon(to),
         {:ok, result} <-
           Maps.Route.plan(
             from: from_coords,
             to: to_coords,
             mode: mode
           ) do
      case result.features do
        %{trip: %{"legs" => legs}} when is_list(legs) ->
          geojson = legs_to_geojson(legs)

          {:noreply,
           socket
           |> assign(directions: result.features, upstream_status: result.upstream_status)
           |> push_event("map:draw_route", %{geojson: geojson})}

        _ ->
          {:noreply,
           assign(socket,
             directions: result.features,
             upstream_status: result.upstream_status
           )}
      end
    else
      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not parse from/to as lat,lon")}

      {:error, _e} ->
        {:noreply,
         socket
         |> assign(directions: %{trip: nil}, upstream_status: "unavailable")
         |> put_flash(:error, "Routing service unavailable")}
    end
  end

  @impl true
  def handle_event("places_clear", _params, socket) do
    {:noreply, assign(socket, places: [])}
  end

  @impl true
  def handle_event("places_search", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_settings", %{"tiles_url" => url, "theme" => theme}, socket) do
    Settings.set("tiles_url", url)
    Settings.set("tiles_theme", theme)

    {:noreply,
     socket
     |> assign(tiles_url: url, theme: theme)
     |> put_flash(:info, "Settings saved")}
  end

  @impl true
  def handle_info(:status_changed, socket) do
    statuses =
      Seeder.known_services()
      |> Enum.map(fn s -> {s.name, safely_snapshot(s.name)} end)
      |> Map.new()

    {:noreply, assign(socket, service_status: statuses)}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp safely_snapshot(name) do
    ServiceState.snapshot(name)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp parse_latlon(str) when is_binary(str) do
    parts = str |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    with [lat_s, lon_s] <- parts,
         {lat, ""} <- Float.parse(lat_s),
         {lon, ""} <- Float.parse(lon_s) do
      {:ok, %{lat: lat, lon: lon}}
    else
      _ -> :error
    end
  end

  defp parse_latlon(_), do: :error

  # M3.1 follow-up: full polyline decoder. Valhalla returns `shape` as a Google-polyline-encoded
  # string per leg. For M3 we emit an empty FeatureCollection — the actual shape decoding can be
  # done client-side (smaller bundle hit) or via a pure-Elixir port of the polyline algorithm.
  defp legs_to_geojson(_legs) do
    %{type: "FeatureCollection", features: []}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen">
      <aside class="w-96 bg-base-100 border-r border-base-300 p-4 overflow-y-auto">
        <.live_component
          module={AtlasWeb.SearchCard}
          id="search-card"
          query={@search_query}
          results={@search_results}
        />
        <.live_component
          module={AtlasWeb.DirectionsCard}
          id="directions-card"
          directions={@directions}
          mode={@mode}
        />
        <.live_component
          module={AtlasWeb.PlacesCard}
          id="places-card"
          places={@places}
        />
        <.live_component
          module={AtlasWeb.SettingsPanel}
          id="settings-panel"
          tiles_url={@tiles_url}
          theme={@theme}
          service_status={@service_status}
        />
        <%= if @upstream_status != "ok" do %>
          <.live_component
            module={AtlasWeb.DegradationBanner}
            id="degradation-banner"
            status={@upstream_status}
          />
        <% end %>
      </aside>

      <div
        id="map"
        phx-hook="Map"
        phx-update="ignore"
        class="flex-1 h-full"
        data-tiles-url={@tiles_url}
        data-theme={@theme}
        data-center="[10.4515, 51.1657]"
        data-zoom="5"
      >
      </div>
    </div>
    """
  end
end
