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
       active_tab: "search",
       search_query: "",
       search_results: [],
       directions: nil,
       mode: "auto",
       places: [],
       route_options: %{"avoid_tolls" => false, "avoid_highways" => false, "avoid_ferries" => false},
       service_status: %{},
       upstream_status: "ok"
     )}
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab}, socket)
      when tab in ~w(search route places settings) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    trimmed = String.trim(q)

    if trimmed == "" do
      {:noreply, assign(socket, search_query: q, search_results: [])}
    else
      result =
        Maps.Search.autocomplete(%{
          query: trimmed,
          limit: 8,
          lang: nil,
          lat: nil,
          lon: nil,
          bbox: nil
        })

      {:noreply,
       socket
       |> assign(
         search_query: q,
         search_results: result.features,
         upstream_status: result.upstream_status
       )
       |> push_event("map:clear_markers", %{})}
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
         {:ok, to_coords} <- parse_latlon(to) do
      result =
        Maps.Route.plan(
          from: from_coords,
          to: to_coords,
          mode: mode
        )

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
    end
  end

  @impl true
  def handle_event("pick_point", %{"field" => field}, socket) when field in ~w(from to) do
    {:noreply, push_event(socket, "map:enter_picker", %{field: field})}
  end

  @impl true
  def handle_event("swap_route", _params, socket) do
    {:noreply, push_event(socket, "map:swap_route", %{})}
  end

  @impl true
  def handle_event("toggle_route_option", %{"option" => option}, socket)
      when option in ~w(avoid_tolls avoid_highways avoid_ferries) do
    options =
      Map.update(socket.assigns.route_options, option, true, fn current -> not current end)

    {:noreply, assign(socket, route_options: options)}
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
  def handle_event("update_theme", %{"theme" => theme}, socket) do
    Settings.set("tiles_theme", theme)
    {:noreply, assign(socket, theme: theme)}
  end

  @impl true
  def handle_event("use_local_tiles", _params, socket) do
    {:noreply, put_flash(socket, :info, "Local tiles selection not yet wired")}
  end

  @impl true
  def handle_event("use_env_tiles", _params, socket) do
    env_url = System.get_env("TILES_URL") || ""
    Settings.set("tiles_url", env_url)
    {:noreply, assign(socket, tiles_url: env_url)}
  end

  @impl true
  def handle_event("toggle_region", %{"name" => _name}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_service", %{"name" => _name}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_auto", %{"name" => _name}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_schedule", %{"name" => _name, "cron" => _cron}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_now", %{"name" => _name}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_selection", _params, socket) do
    {:noreply, put_flash(socket, :info, "Apply selection not yet wired")}
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
    <%= if @upstream_status != "ok" do %>
      <.live_component
        module={AtlasWeb.DegradationBanner}
        id="degradation-banner"
        status={@upstream_status}
      />
    <% end %>

    <div class="fixed inset-0 p-2 sm:p-3 bg-base-200 flex gap-2 sm:gap-3">
      <%!-- Side panel (flat on the page, no card chrome) --%>
      <aside class="flex flex-col flex-none">
        <%!-- Brand header --%>
        <div class="apo-brand px-2.5 py-3 flex items-center gap-2.5 flex-shrink-0">
          <span class="w-2.5 h-2.5 rounded-full bg-primary shadow-sm flex-shrink-0"></span>
          <span class="apo-brand-text font-display font-semibold text-[15px] leading-none tracking-tight whitespace-nowrap text-base-content">
            Dawarich Atlas
          </span>
        </div>

        <div class="flex flex-1 min-h-0">
          <%!-- Icon rail --%>
          <nav class="flex flex-col gap-1 p-1.5 flex-shrink-0">
            <button
              type="button"
              class={"btn btn-square btn-sm " <> tab_class(@active_tab, "search")}
              phx-click="select_tab"
              phx-value-tab="search"
              aria-label="Search"
              title="Search"
            >
              {icon("search", class: "w-5 h-5")}
            </button>
            <button
              type="button"
              class={"btn btn-square btn-sm " <> tab_class(@active_tab, "route")}
              phx-click="select_tab"
              phx-value-tab="route"
              aria-label="Directions"
              title="Directions"
            >
              {icon("route", class: "w-5 h-5")}
            </button>
            <button
              type="button"
              class={"btn btn-square btn-sm " <> tab_class(@active_tab, "places")}
              phx-click="select_tab"
              phx-value-tab="places"
              aria-label="Places"
              title="Places"
            >
              {icon("map-pin", class: "w-5 h-5")}
            </button>
            <button
              type="button"
              class={"btn btn-square btn-sm " <> tab_class(@active_tab, "settings")}
              phx-click="select_tab"
              phx-value-tab="settings"
              aria-label="Settings"
              title="Settings"
            >
              {icon("settings", class: "w-5 h-5")}
            </button>
            <div class="flex-1"></div>
            <button
              type="button"
              class="btn btn-square btn-sm btn-ghost"
              aria-label="Toggle light/dark"
              title="Toggle light/dark"
              onclick="(function(){const r=document.documentElement;const c=r.getAttribute('data-theme');r.setAttribute('data-theme', c==='bunker-brutalist' ? 'forest-patina' : 'bunker-brutalist');})()"
            >
              {icon("moon", class: "w-4 h-4")}
            </button>
          </nav>

          <%!-- Content column: single active tab body (flat, no card chrome) --%>
          <div class="w-[min(85vw,380px)] flex flex-col overflow-hidden">
            <div class={tab_visible_class(@active_tab, "search")}>
              <.live_component
                module={AtlasWeb.SearchCard}
                id="search-card"
                query={@search_query}
                results={@search_results}
              />
            </div>
            <div class={tab_visible_class(@active_tab, "route")}>
              <.live_component
                module={AtlasWeb.DirectionsCard}
                id="directions-card"
                directions={@directions}
                mode={@mode}
                route_options={@route_options}
              />
            </div>
            <div class={tab_visible_class(@active_tab, "places")}>
              <.live_component
                module={AtlasWeb.PlacesCard}
                id="places-card"
                places={@places}
              />
            </div>
            <div class={tab_visible_class(@active_tab, "settings")}>
              <.live_component
                module={AtlasWeb.SettingsPanel}
                id="settings-panel"
                tiles_url={@tiles_url}
                theme={@theme}
                service_status={@service_status}
              />
            </div>
          </div>
        </div>

        <%!-- Attribution --%>
        <div class="apo-brand-text px-2.5 py-2 text-[11px] leading-none text-base-content/50 flex-shrink-0">
          Made by
          <a
            href="https://dawarich.app?utm_source=atlas-map&utm_medium=referral&utm_campaign=atlas-map"
            target="_blank"
            rel="noopener noreferrer"
            class="font-medium text-base-content/70 hover:text-primary transition-colors"
          >
            Dawarich
          </a>
          people
        </div>
      </aside>

      <%!-- Map container --%>
      <div class="relative flex-1 min-w-0 rounded-2xl border border-base-300 bg-base-100 overflow-hidden">
        <div
          id="map"
          phx-hook="Map"
          phx-update="ignore"
          class="absolute inset-0"
          data-tiles-url={@tiles_url}
          data-theme={@theme}
          data-center="[10.4515, 51.1657]"
          data-zoom="5"
        >
        </div>
      </div>
    </div>
    """
  end

  defp tab_class(active, tab) when active == tab, do: "btn-primary"
  defp tab_class(_active, _tab), do: "btn-ghost"

  defp tab_visible_class(active, tab) when active == tab, do: "flex-1 min-h-0"
  defp tab_visible_class(_active, _tab), do: "hidden flex-1 min-h-0"
end
