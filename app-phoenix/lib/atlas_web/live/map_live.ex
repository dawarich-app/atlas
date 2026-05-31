defmodule AtlasWeb.MapLive do
  use AtlasWeb, :live_view

  import Ecto.Query

  alias Atlas.Maps
  alias Atlas.Maps.BasemapPresets
  alias Atlas.Repo
  alias Atlas.Settings
  alias Atlas.Control.{RegionApplier, RegionSelection, Seeder, ServiceState, TilesDownloader}

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
       route_from: "",
       route_to: "",
       places: [],
       route_options: %{"avoid_tolls" => false, "avoid_highways" => false, "avoid_ferries" => false},
       service_status: refresh_service_status(),
       tiles_download: nil,
       active_regions: load_active_regions(),
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
    socket = assign(socket, route_from: from, route_to: to)

    with {:ok, from_coords} <- parse_latlon(from),
         {:ok, to_coords} <- parse_latlon(to),
         {:ok, result} <-
           Maps.Route.plan(
             from: from_coords,
             to: to_coords,
             mode: mode
           ) do
      case result.features do
        %{legs: legs} when is_list(legs) and legs != [] ->
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
  def handle_event("pick_point", %{"field" => field}, socket) when field in ~w(from to) do
    {:noreply, push_event(socket, "map:enter_picker", %{field: field})}
  end

  @impl true
  def handle_event("point_picked", %{"field" => field, "lat" => lat, "lon" => lon}, socket)
      when field in ~w(from to) do
    value = "#{format_coord(lat)},#{format_coord(lon)}"
    key = if field == "from", do: :route_from, else: :route_to
    {:noreply, assign(socket, key, value)}
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
  def handle_event("use_basemap", %{"id" => id}, socket) do
    case BasemapPresets.resolve(id) do
      {:ok, %{url: url, download: false}} when is_binary(url) ->
        Settings.set("tiles_url", url)

        {:noreply,
         socket
         |> assign(tiles_url: url)
         |> push_event("map:set_style", %{url: url})}

      {:ok, %{url: url, download: true}} when is_binary(url) ->
        try do
          # PubSub subscription so we can surface progress; tolerated even if
          # TilesDownloader process isn't running.
          if connected?(socket) do
            Phoenix.PubSub.subscribe(Atlas.PubSub, TilesDownloader.topic())
          end

          case TilesDownloader.download(url) do
            {:ok, _job_id, dest} ->
              local_url = "file://" <> dest
              Settings.set("tiles_url", local_url)

              {:noreply,
               socket
               |> assign(tiles_url: local_url, tiles_download: %{status: :done, dest: dest})
               |> push_event("map:set_style", %{url: local_url})
               |> put_flash(:info, "Tile pack downloaded.")}

            {:error, reason} ->
              {:noreply,
               socket
               |> assign(tiles_download: %{status: :error, reason: inspect(reason)})
               |> put_flash(:error, "Tile pack download failed: #{inspect(reason)}")}
          end
        catch
          :exit, _ ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Download-based presets are unavailable: TilesDownloader is not running on this build."
             )}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Unknown basemap preset")}
    end
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
  def handle_event("toggle_region", %{"name" => name}, socket) do
    existing = Repo.all(from r in RegionSelection, where: r.region_name == ^name)

    case existing do
      [%RegionSelection{active: true} | _] ->
        Repo.delete_all(from r in RegionSelection, where: r.region_name == ^name)

      [%RegionSelection{active: false} = row | _] ->
        row
        |> RegionSelection.changeset(%{active: true})
        |> Repo.update!()

      [] ->
        position = next_region_position()

        %RegionSelection{}
        |> RegionSelection.changeset(%{region_name: name, active: true, position: position})
        |> Repo.insert!()
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_service", %{"name" => name}, socket) do
    snap = safely_snapshot(name)
    currently_enabled = match?(%{enabled?: true}, snap)

    _ =
      try do
        if currently_enabled, do: ServiceState.disable(name), else: ServiceState.enable(name)
      rescue
        _ -> :unavailable
      catch
        :exit, _ -> :unavailable
      end

    {:noreply, assign(socket, service_status: refresh_service_status())}
  end

  @impl true
  def handle_event("toggle_auto", %{"name" => name}, socket) do
    snap = safely_snapshot(name)
    next = not match?(%{auto_update_enabled?: true}, snap)

    _ =
      try do
        ServiceState.set_auto_update(name, next)
      rescue
        _ -> :unavailable
      catch
        :exit, _ -> :unavailable
      end

    {:noreply, assign(socket, service_status: refresh_service_status())}
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
    active =
      Repo.all(from r in RegionSelection, where: r.active == true, order_by: [asc: r.position])
      |> Enum.map(& &1.region_name)

    case active do
      [] ->
        {:noreply, put_flash(socket, :info, "No regions selected")}

      names ->
        try do
          RegionApplier.apply(names)
          {:noreply, put_flash(socket, :info, "Applying #{length(names)} region(s)…")}
        catch
          :exit, _ ->
            {:noreply,
             put_flash(socket, :error, "RegionApplier is not running on this build")}
        end
    end
  end

  @impl true
  def handle_info(:status_changed, socket) do
    {:noreply, assign(socket, service_status: refresh_service_status())}
  end

  def handle_info({:start, job_id, _url, _dest}, socket) do
    {:noreply, assign(socket, tiles_download: %{status: :start, job_id: job_id})}
  end

  def handle_info({:progress, job_id, fraction}, socket) do
    {:noreply, assign(socket, tiles_download: %{status: :progress, job_id: job_id, fraction: fraction})}
  end

  def handle_info({:done, job_id, dest}, socket) do
    {:noreply, assign(socket, tiles_download: %{status: :done, job_id: job_id, dest: dest})}
  end

  def handle_info({:error, job_id, reason}, socket) do
    {:noreply, assign(socket, tiles_download: %{status: :error, job_id: job_id, reason: inspect(reason)})}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp refresh_service_status do
    Seeder.known_services()
    |> Enum.map(fn s -> {s.name, safely_snapshot(s.name)} end)
    |> Map.new()
  end

  defp next_region_position do
    Repo.aggregate(RegionSelection, :max, :position)
    |> case do
      nil -> 0
      n -> n + 1
    end
  end

  defp format_coord(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 6)
  defp format_coord(value) when is_integer(value), do: Integer.to_string(value)
  defp format_coord(value) when is_binary(value), do: value

  # Used by the SettingsPanel's region summary section — pulls the latest
  # active region names from DB. Tolerant of repo errors during tests/dev
  # so a hot-reload doesn't kill the LiveView on boot.
  defp load_active_regions do
    RegionSelection
    |> where(active: true)
    |> order_by(:position)
    |> Repo.all()
    |> Enum.map(& &1.region_name)
  rescue
    _ -> []
  end


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

  defp legs_to_geojson(legs) when is_list(legs) do
    features =
      Enum.flat_map(legs, fn leg ->
        case leg["shape"] do
          shape when is_binary(shape) and shape != "" ->
            coords =
              shape
              |> Atlas.Geometry.Polyline.decode(6)
              |> Enum.map(fn {lat, lon} -> [lon, lat] end)

            [
              %{
                type: "Feature",
                geometry: %{type: "LineString", coordinates: coords},
                properties: %{}
              }
            ]

          _ ->
            []
        end
      end)

    %{type: "FeatureCollection", features: features}
  end

  defp legs_to_geojson(_), do: %{type: "FeatureCollection", features: []}

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
                route_from={@route_from}
                route_to={@route_to}
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
                tiles_download={@tiles_download}
                active_regions={@active_regions}
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
