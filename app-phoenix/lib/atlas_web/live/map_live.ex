defmodule AtlasWeb.MapLive do
  use AtlasWeb, :live_view

  alias Atlas.Geometry.Coord
  alias Atlas.Maps
  alias Atlas.Maps.{Discovery, Poi.Catalog}
  alias Atlas.Settings
  alias AtlasWeb.{RouteDetails, RouteEndpoint, SearchMarkers}

  alias Atlas.Control.{
    ApplyTimeline,
    RegionApplier,
    RegionSelection,
    Safe,
    Seeder,
    ServiceSchedule,
    ServiceState,
    TilesDownloader
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Atlas.PubSub, "control:status")
      Safe.call(fn -> Phoenix.PubSub.subscribe(Atlas.PubSub, RegionApplier.topic()) end)
      Safe.call(fn -> Phoenix.PubSub.subscribe(Atlas.PubSub, TilesDownloader.topic()) end)
      Safe.call(fn -> Phoenix.PubSub.subscribe(Atlas.PubSub, ApplyTimeline.topic()) end)
    end

    {:ok,
     assign(socket,
       page_title: "Atlas",
       tiles_url: Settings.tiles_url(),
       theme: Settings.tiles_theme(),
       active_tab: "search",
       last_map_tab: "search",
       context_restored: false,
       search_city: "",
       search_issues: [],
       search_features: [],
       route_departure: "",
       route_options_open: false,
       route_form_open: true,
       search_query: "",
       search_results: [],
       search_loading: false,
       search_complete: false,
       search_request_id: nil,
       search_count: 0,
       directions: nil,
       route_request_key: nil,
       mode: "auto",
       route_from: "",
       route_to: "",
       route_endpoints: %{"from" => RouteEndpoint.new(), "to" => RouteEndpoint.new()},
       route_focus: nil,
       categories: [],
       search_scope: "all",
       search_bbox: nil,
       search_area_changed: false,
       selected_place: false,
       route_options: %{
         "avoid_tolls" => false,
         "avoid_highways" => false,
         "avoid_ferries" => false
       },
       service_status: refresh_service_status(),
       pending_services: %{},
       transit_switching: nil,
       transit_backend: Settings.transit_backend(),
       tiles_download: Safe.call(fn -> TilesDownloader.status() end, nil),
       basemap_confirm: nil,
       apply_status: Safe.call(fn -> RegionApplier.status() end, nil),
       timeline: Safe.call(fn -> ApplyTimeline.current() end, nil),
       service_logs: nil,
       service_coverage: nil,
       upstream_status: "ok",
       search_status: "ok",
       search_active: -1,
       search_searched: false,
       url_params: %{},
       viewport: nil
     )}
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab}, socket)
      when tab in ~w(search route places settings) do
    {:noreply, activate_tab(socket, if(tab == "places", do: "search", else: tab))}
  end

  def handle_event("open_services", _, socket) do
    send_update(AtlasWeb.SettingsPanel, id: "settings-panel", settings_tab: "services")
    {:noreply, activate_tab(socket, "settings")}
  end

  def handle_event("back_to_map", _, socket),
    do: {:noreply, activate_tab(socket, socket.assigns.last_map_tab)}

  def handle_event("restore_map_context", data, socket) do
    context = AtlasWeb.MapContext.restore(data)
    blank_search = socket.assigns.url_params == %{} and socket.assigns.search_query == ""

    same_search =
      Map.take(context, ~w(search_query search_city categories search_scope search_bbox)a) ==
        Map.take(
          socket.assigns,
          ~w(search_query search_city categories search_scope search_bbox)a
        )

    if socket.assigns.context_restored or not (blank_search or same_search) do
      {:reply, %{}, socket}
    else
      socket = socket |> assign(context) |> assign(context_restored: true)

      socket =
        assign(socket,
          route_from: context.route_endpoints["from"].query,
          route_to: context.route_endpoints["to"].query
        )

      socket = socket |> run_search(context.search_query) |> activate_tab(context.active_tab)

      socket =
        if context.viewport,
          do: push_event(socket, "map:restore_view", %{bbox: context.viewport}),
          else: socket

      {:reply, %{}, socket |> push_route_endpoints() |> maybe_route()}
    end
  end

  def handle_event("search_city", %{"city" => city}, socket) do
    {:noreply, patch_discovery(socket, %{"city" => String.trim(String.slice(city, 0, 100))})}
  end

  def handle_event("back_to_results", _, socket),
    do: {:noreply, assign(socket, selected_place: false)}

  def handle_event("route_place", %{"id" => id, "field" => field}, socket)
      when field in ~w(from to) do
    case Enum.find(socket.assigns.search_features, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      place ->
        {:noreply,
         socket |> activate_tab("route") |> set_endpoint(field, RouteEndpoint.select(place))}
    end
  end

  def handle_event("toggle_route_options", _, socket),
    do: {:noreply, assign(socket, route_options_open: not socket.assigns.route_options_open)}

  def handle_event("toggle_route_form", _, socket),
    do: {:noreply, assign(socket, route_form_open: not socket.assigns.route_form_open)}

  def handle_event("clear_route", _, socket) do
    {:noreply,
     socket
     |> set_endpoint("from", RouteEndpoint.new(), false)
     |> set_endpoint("to", RouteEndpoint.new(), false)
     |> assign(route_form_open: true)
     |> push_route_endpoints()}
  end

  def handle_event("route_departure", %{"departure" => ""}, socket),
    do: {:noreply, socket |> assign(route_departure: "", route_request_key: nil) |> maybe_route()}

  def handle_event("route_departure", %{"departure" => value}, socket) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} ->
        {:noreply, socket |> assign(route_departure: DateTime.to_iso8601(dt)) |> maybe_route()}

      _ ->
        {:noreply, put_flash(socket, :error, "Choose a valid departure time.")}
    end
  end

  # The URL is the single source of truth for the query: the event patches it,
  # `handle_params/3` runs the search. One path serves typing, a shared link and
  # the back button alike, instead of three that can disagree.
  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    if q == socket.assigns.search_query and not socket.assigns.search_loading and
         (not socket.assigns.search_searched or not socket.assigns.search_complete) do
      {:noreply, run_search(socket, q)}
    else
      {:noreply, push_patch(socket, to: search_path(socket, q), replace: true)}
    end
  end

  # Zoom changes only cluster presentation. Never replace a complete dataset
  # with a new ranked subset just because the map moved.
  def handle_event("viewport_changed", %{"bbox" => [_w, _s, _e, _n] = bbox}, socket) do
    case Discovery.bbox(Enum.join(bbox, ",")) do
      nil ->
        {:noreply, socket}

      bbox ->
        socket =
          assign(socket,
            viewport: bbox,
            search_area_changed:
              socket.assigns.search_scope == "area" and
                area_changed?(socket.assigns.search_bbox, bbox)
          )

        if socket.assigns.search_scope == "area" and is_nil(socket.assigns.search_bbox) do
          {:noreply, patch_discovery(socket, %{"bbox" => Enum.join(bbox, ",")})}
        else
          {:noreply, socket}
        end
    end
  end

  def handle_event("toggle_category", %{"id" => id}, socket) do
    if Catalog.find_item(id) do
      categories = socket.assigns.categories

      categories =
        if id in categories, do: List.delete(categories, id), else: Enum.sort([id | categories])

      changes = %{"categories" => Enum.join(categories, ",")}
      changes = if socket.assigns.selected_place, do: Map.put(changes, "q", ""), else: changes
      {:noreply, patch_discovery(socket, changes)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("choose_category", %{"id" => id}, socket) do
    if Catalog.find_item(id) do
      categories = Enum.sort(Enum.uniq([id | socket.assigns.categories]))

      {:noreply,
       patch_discovery(socket, %{"categories" => Enum.join(categories, ","), "q" => ""})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear_categories", _, socket) do
    {:noreply, patch_discovery(socket, %{"categories" => ""})}
  end

  def handle_event("search_scope", %{"scope" => "all"}, socket) do
    {:noreply, patch_discovery(socket, %{"scope" => "", "bbox" => ""})}
  end

  def handle_event("search_scope", %{"scope" => "area"}, socket), do: search_here(socket)
  def handle_event("search_here", _, socket), do: search_here(socket)

  def handle_event("search_reset", _, socket) do
    socket =
      socket
      |> cancel_search()
      |> assign(
        search_query: "",
        search_results: [],
        search_count: 0,
        search_features: [],
        search_city: "",
        search_searched: false,
        search_active: -1,
        selected_place: false
      )
      |> push_results([])

    {:noreply,
     patch_discovery(socket, %{
       "q" => "",
       "city" => "",
       "categories" => "",
       "scope" => "",
       "bbox" => ""
     })}
  end

  def handle_event("search_retry", _, socket),
    do: {:noreply, run_search(socket, socket.assigns.search_query)}

  def handle_event("show_search_results", _params, socket) do
    {:noreply, push_event(socket, "map:fit_results", %{})}
  end

  def handle_event("search_move", %{"dir" => dir}, socket) when dir in [1, -1] do
    count = length(socket.assigns.search_results)

    {:noreply,
     assign(socket, search_active: move_active(socket.assigns.search_active, dir, count))}
  end

  def handle_event("search_commit", _params, socket) do
    # The index guard is load-bearing: `Enum.at(list, -1)` returns the LAST
    # element, so without it Enter with nothing highlighted would fly to the
    # bottom result instead of doing nothing.
    with true <- socket.assigns.search_active >= 0,
         feature when not is_nil(feature) <-
           Enum.at(socket.assigns.search_results, socket.assigns.search_active) do
      {:noreply, select_feature(socket, feature)}
    else
      _ -> {:noreply, socket}
    end
  end

  # Dismiss means dismiss: the pins go with the list, and `search_searched`
  # resets so the panel does not answer a successful search with "No results".
  def handle_event("search_dismiss", _params, socket) do
    {:noreply,
     socket
     |> cancel_search()
     |> assign(search_results: [], search_active: -1, search_searched: false, search_count: 0)
     |> push_results([])}
  end

  @impl true
  def handle_event("select_result", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.search_results, &(&1.id == id)) do
      nil -> {:noreply, socket}
      feature -> {:noreply, select_feature(socket, feature)}
    end
  end

  @impl true
  def handle_event("dismiss_timeline", _params, socket) do
    Safe.call(fn -> ApplyTimeline.dismiss() end)
    {:noreply, assign(socket, timeline: nil)}
  end

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket)
      when mode in ~w(auto bicycle pedestrian transit) do
    {:noreply, socket |> assign(mode: mode) |> maybe_route()}
  end

  @impl true
  def handle_event("route_changed", %{"from" => from, "to" => to} = params, socket) do
    socket = socket |> sync_route_inputs(from, to) |> maybe_route()
    field = List.first(params["_target"] || [])
    {:noreply, if(field in ~w(from to), do: assign(socket, route_focus: field), else: socket)}
  end

  def handle_event("route_focus", %{"field" => field}, socket) when field in ~w(from to) do
    {:noreply, assign(socket, route_focus: field)}
  end

  def handle_event("route_retry", %{"field" => field}, socket) when field in ~w(from to) do
    {:noreply, socket |> search_endpoint(field) |> assign(route_focus: field)}
  end

  def handle_event("route_dismiss", _, socket), do: {:noreply, assign(socket, route_focus: nil)}

  def handle_event("route_move", %{"field" => field, "query" => query, "dir" => dir}, socket)
      when field in ~w(from to) and dir in [1, -1] do
    endpoint = socket.assigns.route_endpoints[field]

    if endpoint.query == query do
      endpoint = %{endpoint | active: move_active(endpoint.active, dir, length(endpoint.results))}
      {:noreply, socket |> put_endpoint(field, endpoint) |> assign(route_focus: field)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("route_select", %{"field" => field, "query" => query} = params, socket)
      when field in ~w(from to) do
    endpoint = socket.assigns.route_endpoints[field]

    index =
      case Integer.parse(to_string(params["index"] || endpoint.active)) do
        {index, ""} when index >= 0 -> index
        _ -> -1
      end

    place = if index >= 0 and endpoint.query == query, do: Enum.at(endpoint.results, index)

    {:noreply,
     if(place, do: set_endpoint(socket, field, RouteEndpoint.select(place)), else: socket)}
  end

  def handle_event("route", %{"from" => from, "to" => to} = params, socket) do
    mode = Map.get(params, "mode", socket.assigns.mode)

    socket =
      socket
      |> clear_flash()
      |> sync_route_inputs(from, to)
      |> assign(mode: mode)
      |> then(&assign(&1, route_request_key: route_request_key(&1)))

    with {:ok, from_coords} <- resolve_endpoint(socket, "from", from),
         {:ok, to_coords} <- resolve_endpoint(socket, "to", to),
         {:ok, result} <-
           plan_route(
             mode,
             from_coords,
             to_coords,
             Map.put(socket.assigns.route_options, "departure", socket.assigns.route_departure)
           ) do
      socket = assign(socket, upstream_status: result.upstream_status)
      features = RouteDetails.prepare(result.features, mode)

      case RouteDetails.legs(features) do
        [_ | _] = legs ->
          {:noreply,
           socket
           |> assign(directions: features, route_form_open: false)
           |> push_event("map:draw_route", %{geojson: Coord.legs_to_geojson(legs)})}

        [] ->
          # Clear any stale line and tell the user nothing was found.
          {:noreply,
           socket
           |> assign(directions: nil)
           |> push_event("map:draw_route", %{geojson: Coord.legs_to_geojson([])})
           |> put_flash(:info, "No route found for this trip.")}
      end
    else
      {:error, {:endpoint, field}} ->
        {:noreply,
         socket
         |> clear_route()
         |> assign(route_focus: field)
         |> put_flash(
           :error,
           "Choose a #{String.capitalize(field)} search result or enter valid coordinates (latitude, longitude)."
         )}

      {:error, :invalid_mode} ->
        {:noreply,
         socket |> clear_route() |> put_flash(:error, "Choose Drive, Bike, Walk or Transit.")}

      {:error, %Maps.Upstream.Client.BadResponse{status: status}}
      when status in [400, 404, 422] ->
        {:noreply,
         socket
         |> clear_route()
         |> assign(upstream_status: "ok")
         |> put_flash(
           :info,
           "No route found. Check that both points are inside the loaded region."
         )}

      {:error, _e} ->
        {:noreply,
         socket
         |> clear_route()
         |> assign(upstream_status: "unavailable")
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
    value = "#{Coord.format(lat)},#{Coord.format(lon)}"
    {:noreply, set_endpoint(socket, field, RouteEndpoint.new(value))}
  end

  @impl true
  def handle_event("swap_route", _params, socket) do
    endpoints = socket.assigns.route_endpoints

    {:noreply,
     socket
     |> set_endpoint("from", endpoints["to"], false)
     |> set_endpoint("to", endpoints["from"], false)
     |> push_route_endpoints()
     |> maybe_route()}
  end

  @impl true
  def handle_event("toggle_route_option", %{"option" => option}, socket)
      when option in ~w(avoid_tolls avoid_highways avoid_ferries) do
    options =
      Map.update(socket.assigns.route_options, option, true, fn current -> not current end)

    {:noreply, socket |> assign(route_options: options) |> maybe_route()}
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
  def handle_event("confirm_basemap", %{"id" => id}, socket) do
    with {:ok, %{url: url, download: true} = preset} <- Atlas.Maps.BasemapPresets.resolve(id),
         true <- is_binary(url) do
      confirm = %{id: id, label: preset[:label] || id, size_bytes: probed_size(url)}
      {:noreply, assign(socket, basemap_confirm: confirm)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Unknown basemap preset")}
    end
  end

  @impl true
  def handle_event("cancel_basemap_confirm", _params, socket) do
    {:noreply, assign(socket, basemap_confirm: nil)}
  end

  @impl true
  def handle_event("use_basemap", %{"id" => id}, socket) do
    socket = assign(socket, basemap_confirm: nil)

    case Atlas.Tiles.Basemap.apply(id) do
      {:set_style, url} ->
        {:noreply, socket |> assign(tiles_url: url) |> push_event("map:set_style", %{url: url})}

      {:download_started, job_id, _dest} ->
        {:noreply,
         socket
         |> assign(tiles_download: %{status: :running, job_id: job_id, progress: 0.0})
         |> put_flash(:info, "Tile pack download started — progress shows in the Basemap tab.")}

      {:download_failed, reason} ->
        message = AtlasWeb.AdminErrorComponents.format_error(reason)

        {:noreply,
         socket
         |> assign(tiles_download: %{status: :error, reason: message})
         |> put_flash(:error, "Tile pack download failed: #{message}")}

      :downloader_unavailable ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Download-based presets are unavailable: TilesDownloader is not running on this build."
         )}

      :unknown ->
        {:noreply, put_flash(socket, :error, "Unknown basemap preset")}
    end
  end

  @impl true
  def handle_event("use_env_tiles", _params, socket) do
    env_url = System.get_env("TILES_URL") || ""
    Settings.set("tiles_url", env_url)
    {:noreply, assign(socket, tiles_url: env_url)}
  end

  @impl true
  def handle_event("toggle_region", %{"name" => name}, socket) do
    RegionSelection.toggle(name)
    send_update(AtlasWeb.SettingsPanel, id: "settings-panel")
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_regions", _params, socket) do
    RegionSelection.clear()
    send_update(AtlasWeb.SettingsPanel, id: "settings-panel")
    {:noreply, socket}
  end

  @impl true
  def handle_event("discard_settings_changes", _params, socket) do
    {:ok, _} = RegionSelection.discard_changes()
    send_update(AtlasWeb.SettingsPanel, id: "settings-panel", pending_services: %{})
    {:noreply, assign(socket, pending_services: %{})}
  end

  @impl true
  def handle_event("open_service_coverage", %{"name" => name}, socket)
      when name in ~w(photon libpostal placeholder valhalla overpass otp motis whosonfirst) do
    {:noreply,
     socket
     |> cancel_async(:service_coverage)
     |> assign(service_coverage: %{name: name, loading: true, result: nil})
     |> start_async(:service_coverage, fn -> Atlas.Control.ServiceCoverage.read(name) end)}
  end

  @impl true
  def handle_event("close_service_coverage", _params, socket) do
    {:noreply, socket |> cancel_async(:service_coverage) |> assign(service_coverage: nil)}
  end

  @impl true
  def handle_event("open_logs", %{"name" => name}, socket) do
    if previous = socket.assigns.service_logs do
      Phoenix.PubSub.unsubscribe(Atlas.PubSub, "logs:#{previous.name}")
    end

    Phoenix.PubSub.subscribe(Atlas.PubSub, "logs:#{name}")

    tailer =
      case Safe.call(fn -> Atlas.Control.LogTailer.Supervisor.start_tail(name) end) do
        :unavailable -> :error
        _ -> :ok
      end

    # An already-running tailer (attached at boot) consumed the compose
    # history before this viewer subscribed — replay its buffer.
    recent = Safe.call(fn -> Atlas.Control.LogTailer.recent(name) end, [])
    lines = recent |> List.wrap() |> Enum.reverse() |> Enum.take(500)

    {:noreply,
     assign(socket, service_logs: %{name: name, lines: lines, eof: nil, tailer: tailer})}
  end

  @impl true
  def handle_event("close_logs", _params, socket) do
    if logs = socket.assigns.service_logs do
      Phoenix.PubSub.unsubscribe(Atlas.PubSub, "logs:#{logs.name}")
    end

    {:noreply, assign(socket, service_logs: nil)}
  end

  @impl true
  def handle_event("retry_apply", _params, socket) do
    case RegionSelection.active_names() do
      [] -> {:noreply, put_flash(socket, :error, "No regions selected")}
      names -> {:noreply, start_region_apply(socket, names)}
    end
  end

  @impl true
  def handle_event("select_transit", %{"name" => name}, socket) when name in ~w(otp motis) do
    if not is_nil(socket.assigns.transit_switching) or
         (name == socket.assigns.transit_backend and
            match?(%{enabled?: true}, Safe.snapshot(name))) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(
         transit_switching: name,
         pending_services: Map.drop(socket.assigns.pending_services, ~w(otp motis))
       )
       |> start_async(:transit_switch, fn -> Atlas.Control.DockerCompose.select_transit(name) end)}
    end
  end

  def handle_event("toggle_service", %{"name" => name}, socket) do
    current = match?(%{enabled?: true}, Safe.snapshot(name))
    pending = socket.assigns.pending_services
    desired = not Map.get(pending, name, current)

    pending =
      if desired == current,
        do: Map.delete(pending, name),
        else: Map.put(pending, name, desired)

    {:noreply, assign(socket, pending_services: pending)}
  end

  @impl true
  def handle_event("toggle_auto", %{"name" => name}, socket) do
    snap = Safe.snapshot(name)
    next = not match?(%{auto_update_enabled?: true}, snap)

    Safe.call(fn -> ServiceState.set_auto_update(name, next) end)

    {:noreply, assign(socket, service_status: refresh_service_status())}
  end

  @impl true
  def handle_event("save_schedule", %{"name" => name, "cron" => cron}, socket) do
    trimmed = String.trim(cron)

    cond do
      trimmed == "" ->
        ServiceSchedule.persist!(name, nil)
        {:noreply, put_flash(socket, :info, "Schedule cleared for #{name}")}

      ServiceSchedule.valid?(trimmed) ->
        ServiceSchedule.persist!(name, trimmed)
        {:noreply, put_flash(socket, :info, "Schedule updated for #{name}")}

      true ->
        {:noreply, put_flash(socket, :error, "Invalid cron expression")}
    end
  end

  @impl true
  def handle_event("update_now", %{"name" => name}, socket) do
    case Safe.call(fn ->
           %{name: name} |> Atlas.Control.Jobs.UpdateService.new() |> Oban.insert()
         end) do
      :unavailable ->
        {:noreply, put_flash(socket, :error, "Update queue unavailable on this build")}

      _ ->
        {:noreply, put_flash(socket, :info, "Update enqueued for #{name}")}
    end
  end

  @impl true
  def handle_event("apply_selection", _params, socket) do
    pending = socket.assigns.pending_services
    Enum.each(pending, &apply_service_toggle/1)

    {region_result, region_names} =
      case RegionSelection.active_names() do
        [] ->
          if RegionSelection.pending_change?() do
            RegionSelection.mark_applied!()
            {:selection_cleared, []}
          else
            {:no_region, []}
          end

        names ->
          if Safe.call(fn -> RegionSelection.pending_change?() end, true) do
            {Safe.call(fn -> RegionApplier.start(names) end), names}
          else
            # Selection unchanged since the last apply — only tools to do.
            {:no_region, []}
          end
      end

    socket = assign(socket, pending_services: %{}, service_status: refresh_service_status())
    send_update(AtlasWeb.SettingsPanel, id: "settings-panel", pending_services: %{})

    case AtlasWeb.MapLive.ApplyFlash.message(map_size(pending), region_result, region_names) do
      {:info, message} ->
        apply_status =
          case region_result do
            {:ok, job_id} ->
              Safe.call(fn -> RegionSelection.mark_applied!() end)
              %{job_id: job_id, regions: region_names, phase: :downloading, progress: nil}

            _ ->
              socket.assigns.apply_status
          end

        {:noreply, socket |> assign(apply_status: apply_status) |> put_flash(:info, message)}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    if Atlas.Control.Onboarding.first_run?() do
      {:noreply, push_navigate(socket, to: ~p"/setup")}
    else
      handle_map_params(params, uri, socket)
    end
  end

  defp activate_tab(socket, tab) do
    map_tab = if tab == "settings", do: socket.assigns.last_map_tab, else: tab

    socket
    |> assign(active_tab: tab, last_map_tab: map_tab)
    |> push_event("map:active_tab", %{tab: map_tab})
  end

  defp handle_map_params(params, _uri, socket) do
    q = Map.get(params, "q", "")
    city = String.slice(Map.get(params, "city", ""), 0, 100)
    categories = Discovery.category_ids(params["categories"])
    scope = if params["scope"] == "area", do: "area", else: "all"
    bbox = if scope == "area", do: Discovery.bbox(params["bbox"]), else: nil

    changed =
      {q, city, categories, scope, bbox} !=
        {socket.assigns.search_query, socket.assigns.search_city, socket.assigns.categories,
         socket.assigns.search_scope, socket.assigns.search_bbox}

    socket =
      assign(socket,
        url_params: Map.drop(params, ["q"]),
        search_city: city,
        categories: categories,
        search_scope: scope,
        search_bbox: bbox,
        search_area_changed: scope == "area" and area_changed?(bbox, socket.assigns.viewport)
      )

    if changed and connected?(socket) do
      {:noreply, run_search(socket, q)}
    else
      {:noreply, assign(socket, search_query: q)}
    end
  end

  @impl true
  def handle_info(:status_changed, socket) do
    backend = Settings.transit_backend()
    changed = backend != socket.assigns.transit_backend
    socket = assign(socket, service_status: refresh_service_status(), transit_backend: backend)

    socket =
      if changed and socket.assigns.mode == "transit", do: clear_route(socket), else: socket

    socket =
      if socket.assigns.mode == "transit" and
           match?(%{status: :ready}, socket.assigns.service_status[backend]),
         do: maybe_route(socket),
         else: socket

    {:noreply, socket}
  end

  def handle_info({:log_line, line}, socket) do
    case socket.assigns.service_logs do
      nil ->
        {:noreply, socket}

      logs ->
        lines = Enum.take([line | logs.lines], 500)
        {:noreply, assign(socket, service_logs: %{logs | lines: lines})}
    end
  end

  def handle_info({:log_eof, code}, socket) do
    case socket.assigns.service_logs do
      nil -> {:noreply, socket}
      logs -> {:noreply, assign(socket, service_logs: %{logs | eof: code})}
    end
  end

  def handle_info({:apply_start, %{job_id: job_id, regions: regions}}, socket) do
    {:noreply,
     assign(socket,
       apply_status: %{job_id: job_id, regions: regions, phase: :downloading, progress: nil}
     )}
  end

  def handle_info({:apply_done, %{job_id: job_id, regions: regions}}, socket) do
    if match?(%{job_id: ^job_id}, socket.assigns.apply_status) do
      {:noreply,
       socket
       |> assign(apply_status: nil)
       |> put_flash(:info, "Regions applied: #{Enum.join(regions, ", ")}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:apply_error, %{job_id: job_id, phase: phase, reason: reason}}, socket) do
    if match?(%{job_id: ^job_id}, socket.assigns.apply_status) do
      status =
        socket.assigns.apply_status
        |> Map.put(:error, reason)
        |> Map.put(:phase, phase)

      {:noreply,
       socket
       |> assign(apply_status: status)
       |> put_flash(:error, "Region apply failed (#{phase}): #{reason}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:start, job_id, _url, _dest}, socket) do
    {:noreply, assign(socket, tiles_download: %{status: :running, job_id: job_id, progress: 0.0})}
  end

  def handle_info({:progress, job_id, fraction}, socket) do
    {:noreply,
     assign(socket, tiles_download: %{status: :running, job_id: job_id, progress: fraction})}
  end

  def handle_info({:done, job_id, dest}, socket) do
    local_url = TilesDownloader.public_url(dest)

    {:noreply,
     socket
     |> assign(
       tiles_url: local_url,
       tiles_download: %{status: :done, job_id: job_id, dest: dest, progress: 1.0}
     )
     |> push_event("map:set_style", %{url: local_url})
     |> put_flash(:info, "Tile pack downloaded.")}
  end

  def handle_info({:error, job_id, reason}, socket) do
    {:noreply,
     socket
     |> assign(tiles_download: %{status: :error, job_id: job_id, reason: reason})
     |> put_flash(:error, "Tile pack download failed: #{reason}")}
  end

  def handle_info({:timeline, timeline}, socket) do
    {:noreply, assign(socket, :timeline, timeline)}
  end

  def handle_info({:search_progress, id, result}, %{assigns: %{search_request_id: id}} = socket) do
    {:noreply, apply_search_result(socket, result)}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  # Rails used the same two-character floor: one letter matches most of the
  # planet, so it costs a Photon round trip per keystroke to return noise.
  @min_query_length 2

  @search_list_limit 40

  # Keeps whatever else is in the URL (a `tab`, say) and drops `q` entirely when
  # the box is empty, so a cleared search leaves `/` rather than `/?q=`.
  defp search_here(%{assigns: %{viewport: nil}} = socket), do: {:noreply, socket}

  defp search_here(socket) do
    {:noreply,
     patch_discovery(socket, %{
       "scope" => "area",
       "bbox" => Enum.join(socket.assigns.viewport, ",")
     })}
  end

  defp area_changed?(nil, _), do: false
  defp area_changed?(_, nil), do: false

  defp area_changed?(before, after_bbox) do
    Enum.zip(before, after_bbox) |> Enum.any?(fn {a, b} -> abs(a - b) > 0.00001 end)
  end

  defp patch_discovery(socket, changes) do
    params =
      socket.assigns.url_params |> Map.put("q", socket.assigns.search_query) |> Map.merge(changes)

    params = Map.reject(params, fn {_key, value} -> value in [nil, ""] end)
    path = if params == %{}, do: ~p"/", else: ~p"/?#{params}"
    push_patch(socket, to: path, replace: true)
  end

  defp search_path(socket, q) do
    params =
      socket.assigns
      |> Map.get(:url_params, %{})
      |> then(fn p -> if String.trim(q) == "", do: p, else: Map.put(p, "q", q) end)

    if params == %{}, do: ~p"/", else: ~p"/?#{params}"
  end

  defp searchable?(q) when is_binary(q), do: String.length(String.trim(q)) >= @min_query_length
  defp searchable?(_), do: false

  defp run_search(socket, q) do
    if (searchable?(q) or (String.trim(q) == "" and socket.assigns.categories != [])) and
         (socket.assigns.search_scope == "all" or not is_nil(socket.assigns.search_bbox)) do
      dispatch_search(socket, q)
    else
      # The markers go with the list. Escape cleared them; backspacing did not,
      # so emptying the box left every pin stranded on the map.
      socket
      |> cancel_search()
      |> assign(
        search_query: q,
        search_count: 0,
        search_results: [],
        search_active: -1,
        search_searched: false
      )
      |> push_results([])
    end
  end

  defp dispatch_search(socket, q) do
    owner = self()
    socket_city = socket.assigns.search_city
    request_id = make_ref()
    categories = socket.assigns.categories

    opts =
      if socket.assigns.search_scope == "area", do: [bbox: socket.assigns.search_bbox], else: []

    socket
    |> cancel_search()
    |> assign(
      search_query: q,
      search_results: [],
      search_count: 0,
      search_status: "ok",
      search_active: -1,
      search_searched: true,
      search_loading: true,
      search_complete: false,
      search_request_id: request_id,
      selected_place:
        if(q == socket.assigns.search_query, do: socket.assigns.selected_place, else: false)
    )
    |> push_results([])
    |> start_async(:map_search, fn ->
      Discovery.run(
        q,
        categories,
        Keyword.put(Keyword.put(opts, :city, socket_city), :on_progress, fn result ->
          send(owner, {:search_progress, request_id, result})
        end)
      )
    end)
  end

  defp cancel_search(socket) do
    socket
    |> cancel_async(:map_search)
    |> assign(search_request_id: nil, search_loading: false, search_complete: false)
    |> push_event("map:search_loading", %{loading: false})
  end

  defp apply_search_result(socket, result) do
    socket
    |> assign(
      search_results: Enum.take(result.suggestions, @search_list_limit),
      search_features: result.features,
      search_issues: Map.get(result, :issues, []),
      search_count: length(result.features),
      search_complete: result.complete,
      search_status:
        if(result.features == [] and :upstream in Map.get(result, :issues, []),
          do: "unavailable",
          else: "ok"
        )
    )
    |> push_results(result.features)
  end

  @impl true
  def handle_async(:transit_switch, {:ok, {:ok, _}}, socket) do
    {:noreply,
     socket
     |> assign(
       transit_switching: nil,
       transit_backend: Settings.transit_backend(),
       service_status: refresh_service_status()
     )
     |> put_flash(:info, "Transit engine selected. Routes are available when its graph is ready.")}
  end

  def handle_async(:transit_switch, result, socket) do
    detail =
      case result do
        {:ok, {:error, _, message}} -> String.slice(message, 0, 240)
        _ -> "Service control is unavailable"
      end

    {:noreply,
     socket
     |> assign(transit_switching: nil)
     |> put_flash(:error, "Could not switch transit engine: " <> detail)}
  end

  def handle_async(:service_coverage, {:ok, result}, socket) do
    case socket.assigns.service_coverage do
      nil ->
        {:noreply, socket}

      coverage ->
        {:noreply, assign(socket, service_coverage: %{coverage | loading: false, result: result})}
    end
  end

  def handle_async(:service_coverage, {:exit, _reason}, socket) do
    handle_async(
      :service_coverage,
      {:ok, %{entries: [], note: "Dataset metadata is currently unavailable."}},
      socket
    )
  end

  def handle_async(:map_search, {:ok, result}, socket) do
    {:noreply, socket |> assign(search_loading: false) |> apply_search_result(result)}
  end

  def handle_async(:map_search, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(search_loading: false, search_complete: false, search_status: "unavailable")
     |> push_event("map:search_loading", %{loading: false})}
  end

  def handle_async({:route_search, field}, {:ok, {query, result}}, socket) do
    endpoint = socket.assigns.route_endpoints[field]

    if endpoint.query == query and endpoint.status == :loading do
      endpoint =
        case result do
          {:ok, results} -> %{endpoint | results: results, status: :ready}
          {:error, _} -> %{endpoint | results: [], status: :error}
        end

      {:noreply, put_endpoint(socket, field, endpoint)}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:route_search, field}, {:exit, reason}, socket) do
    endpoint = socket.assigns.route_endpoints[field]

    if endpoint.status == :loading and reason != {:shutdown, :cancel} do
      {:noreply, put_endpoint(socket, field, %{endpoint | status: :error})}
    else
      {:noreply, socket}
    end
  end

  defp sync_route_inputs(socket, from, to) do
    previous_points = route_points(socket)

    socket =
      Enum.reduce([{"from", from}, {"to", to}], socket, fn {field, query}, socket ->
        if socket.assigns.route_endpoints[field].query == query do
          socket
        else
          endpoint = RouteEndpoint.new(query)

          socket =
            socket
            |> cancel_async({:route_search, field})
            |> invalidate_route()
            |> put_endpoint(field, endpoint)

          search_endpoint(socket, field)
        end
      end)

    if route_points(socket) != previous_points, do: push_route_endpoints(socket), else: socket
  end

  defp search_endpoint(socket, field) do
    endpoint = socket.assigns.route_endpoints[field]
    query = endpoint.query

    if endpoint.coords == nil and endpoint.status != :invalid and
         String.length(String.trim(query)) >= 2 do
      viewport = socket.assigns.viewport

      socket
      |> cancel_async({:route_search, field})
      |> put_endpoint(field, %{endpoint | status: :loading, results: [], active: -1})
      |> start_async({:route_search, field}, fn ->
        {query, RouteEndpoint.search(query, viewport)}
      end)
    else
      socket
    end
  end

  defp put_endpoint(socket, field, endpoint) do
    key = if field == "from", do: :route_from, else: :route_to

    socket
    |> assign(key, endpoint.query)
    |> assign(route_endpoints: Map.put(socket.assigns.route_endpoints, field, endpoint))
  end

  defp set_endpoint(socket, field, endpoint, notify_map \\ true) do
    socket =
      socket
      |> cancel_async({:route_search, field})
      |> invalidate_route()
      |> put_endpoint(field, %{
        endpoint
        | results: [],
          active: -1,
          status: if(endpoint.coords, do: :selected, else: :idle)
      })
      |> assign(route_focus: nil)
      |> search_endpoint(field)
      |> push_event("route:endpoint", %{field: field, value: endpoint.query})

    if notify_map, do: socket |> push_route_endpoints() |> maybe_route(), else: socket
  end

  defp push_route_endpoints(socket) do
    push_event(socket, "map:set_route_endpoints", %{points: route_points(socket)})
  end

  defp route_points(socket) do
    for field <- ~w(from to),
        endpoint = socket.assigns.route_endpoints[field],
        coords = endpoint.coords,
        not is_nil(coords) do
      %{field: field, lat: coords.lat, lon: coords.lon, label: endpoint.query}
    end
  end

  defp invalidate_route(socket) do
    socket = assign(socket, route_request_key: nil)
    if socket.assigns.directions, do: clear_route(socket), else: socket
  end

  defp route_request_key(socket) do
    from = socket.assigns.route_endpoints["from"].coords
    to = socket.assigns.route_endpoints["to"].coords

    if from && to,
      do:
        {from, to, socket.assigns.mode, socket.assigns.route_options,
         socket.assigns.transit_backend, socket.assigns.route_departure}
  end

  defp maybe_route(socket) do
    key = route_request_key(socket)

    if key && key != socket.assigns.route_request_key do
      {:noreply, socket} =
        handle_event(
          "route",
          %{"from" => socket.assigns.route_from, "to" => socket.assigns.route_to},
          socket
        )

      socket
    else
      socket
    end
  end

  defp resolve_endpoint(socket, field, value) do
    case RouteEndpoint.resolve(socket.assigns.route_endpoints[field], value) do
      {:ok, coords} -> {:ok, coords}
      :error -> {:error, {:endpoint, field}}
    end
  end

  # One event replaces the whole marker set, mirroring the Rails map: every
  # result is a pin, so you can see where the matches are before choosing one.
  # Replacing wholesale also removes the clear-then-add ordering that let a
  # pan-triggered refresh wipe the pin a user had just dropped.
  defp push_results(socket, features) do
    push_event(socket, "map:set_results", %{
      points: SearchMarkers.points(features),
      loading: socket.assigns.search_loading
    })
  end

  defp select_feature(socket, feature) do
    coords = feature.coords

    socket
    |> cancel_async(:map_search)
    |> assign(
      selected_place: feature,
      search_active: -1,
      search_loading: false,
      search_request_id: nil
    )
    |> push_event("map:fly_to", %{lat: coords.lat, lon: coords.lon, zoom: 14})
  end

  # Wraps at both ends, matching the Rails list. `-1` means "nothing highlighted"
  # and needs its own clauses rather than arithmetic: `Integer.mod(-1 + -1, 3)`
  # is 1, but ArrowUp from nothing must land on the last row.
  defp move_active(_current, _dir, 0), do: -1
  defp move_active(-1, 1, _count), do: 0
  defp move_active(-1, -1, count), do: count - 1
  defp move_active(current, dir, count), do: Integer.mod(current + dir, count)

  # Transit goes to the selected engine; everything else (auto/bicycle/pedestrian) to Valhalla.
  # Valhalla.route/2 raises on an unknown costing, so transit must never reach it.
  defp plan_route("transit", from, to, options) do
    opts = [from: from, to: to]

    opts =
      if options["departure"] in [nil, ""],
        do: opts,
        else: Keyword.put(opts, :datetime, options["departure"])

    Maps.Transit.plan(opts)
  end

  defp plan_route(mode, from, to, options) when mode in ~w(auto bicycle pedestrian) do
    Maps.Route.plan(from: from, to: to, mode: mode, options: costing_options(options))
  end

  defp plan_route(_mode, _from, _to, _options), do: {:error, :invalid_mode}

  defp clear_route(socket) do
    socket
    |> assign(directions: nil)
    |> push_event("map:draw_route", %{geojson: Coord.legs_to_geojson([])})
  end

  # The route-option toggles are stored string-keyed; Valhalla's costing options
  # want atoms. Whitelist the three known keys rather than String.to_atom/1.
  defp costing_options(options) when is_map(options) do
    %{
      avoid_tolls: Map.get(options, "avoid_tolls", false),
      avoid_highways: Map.get(options, "avoid_highways", false),
      avoid_ferries: Map.get(options, "avoid_ferries", false)
    }
  end

  defp costing_options(_), do: %{}

  defp refresh_service_status do
    Seeder.known_services()
    |> Enum.map(fn s -> {s.name, Safe.snapshot(s.name)} end)
    |> Map.new()
  end

  defp probed_size(url) do
    case Safe.call(fn -> TilesDownloader.probe_size(url) end) do
      {:ok, bytes} when is_integer(bytes) -> bytes
      _ -> nil
    end
  end

  defp apply_service_toggle({name, desired}) do
    Safe.call(fn ->
      if desired, do: ServiceState.enable(name), else: ServiceState.disable(name)
    end)
  end

  defp start_region_apply(socket, names) do
    case Safe.call(fn -> RegionApplier.start(names) end) do
      {:ok, job_id} ->
        assign(socket,
          apply_status: %{job_id: job_id, regions: names, phase: :downloading, progress: nil}
        )

      other ->
        {:error, message} = AtlasWeb.MapLive.ApplyFlash.message(0, other, names)
        put_flash(socket, :error, message)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @upstream_status != "ok" do %>
      <AtlasWeb.DegradationBanner.degradation_banner
        id="degradation-banner"
        status={@upstream_status}
      />
    <% end %>

    <div id="atlas-workspace" phx-hook="MapWorkspace" data-context={Jason.encode!(AtlasWeb.MapContext.dump(assigns))} data-settings-open={to_string(@active_tab == "settings")} class="fixed inset-0 p-2 sm:p-3 bg-base-200 flex flex-col md:flex-row gap-2 sm:gap-3">
      <AtlasWeb.SidePanel.side_panel
        active_tab={@active_tab}
        search_query={@search_query}
        selected_place={@selected_place}
        search_city={@search_city}
        search_issues={@search_issues}
        search_results={@search_results}
        search_loading={@search_loading}
        search_complete={@search_complete}
        search_count={@search_count}
        search_status={@search_status}
        search_active={@search_active}
        search_searched={@search_searched}
        directions={@directions}
        mode={@mode}
        route_endpoints={@route_endpoints}
        route_focus={@route_focus}
        route_from={@route_from}
        route_to={@route_to}
        route_options={@route_options}
        route_options_open={@route_options_open}
        route_form_open={@route_form_open}
        route_departure={@route_departure}
        categories={@categories}
        scope={@search_scope}
        area_changed={@search_area_changed}
        viewport_ready={not is_nil(@viewport)}
        search_service={if String.trim(@search_query) == "" and @categories != [], do: "overpass", else: "photon"}
        tiles_url={@tiles_url}
        theme={@theme}
        service_status={@service_status}
        pending_services={@pending_services}
        transit_backend={@transit_backend}
        transit_switching={@transit_switching}
        tiles_download={@tiles_download}
        basemap_confirm={@basemap_confirm}
        timeline={@timeline}
      />

      <div id="map-frame" class="relative flex-1 min-w-0 min-h-0 rounded-2xl border border-base-300 bg-base-100 overflow-hidden">
        <div
          id="map"
          phx-hook="Map"
          phx-update="ignore"
          class="absolute inset-0"
          data-tiles-url={@tiles_url}
          data-theme={@theme}
          data-center="[10.4515, 51.1657]"
          data-bounds={if @search_bbox, do: Jason.encode!(@search_bbox)}
          data-zoom="5"
        >
        </div>
      </div>
    </div>

    <AtlasWeb.Settings.CoverageModal.coverage_modal :if={@service_coverage} coverage={@service_coverage} />

    <AtlasWeb.Settings.LogsModal.logs_modal
      :if={@service_logs}
      name={@service_logs.name}
      snapshot={@service_status[@service_logs.name]}
      logs={@service_logs}
    />
    """
  end
end
