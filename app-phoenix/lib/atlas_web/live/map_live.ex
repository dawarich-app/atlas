defmodule AtlasWeb.MapLive do
  use AtlasWeb, :live_view

  alias Atlas.Geometry.Coord
  alias Atlas.Maps
  alias Atlas.Settings
  alias AtlasWeb.SearchMarkers

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
       search_query: "",
       search_results: [],
       directions: nil,
       mode: "auto",
       route_from: "",
       route_to: "",
       places: [],
       route_options: %{
         "avoid_tolls" => false,
         "avoid_highways" => false,
         "avoid_ferries" => false
       },
       service_status: refresh_service_status(),
       pending_services: %{},
       tiles_download: Safe.call(fn -> TilesDownloader.status() end, nil),
       basemap_confirm: nil,
       apply_status: Safe.call(fn -> RegionApplier.status() end, nil),
       timeline: Safe.call(fn -> ApplyTimeline.current() end, nil),
       service_logs: nil,
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
    {:noreply, assign(socket, active_tab: tab)}
  end

  # The URL is the single source of truth for the query: the event patches it,
  # `handle_params/3` runs the search. One path serves typing, a shared link and
  # the back button alike, instead of three that can disagree.
  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: search_path(socket, q), replace: true)}
  end

  # The map reports its viewport after every pan/zoom. Re-running the active
  # query against the new bounds is what makes a brand search ("McDonald's")
  # answer "which ones can I see" instead of "the global top N".
  #
  # A move we caused ourselves is exempt. Picking a result flies the map, and
  # treating that flight as a pan re-ran the query still sitting in the box,
  # restoring the list and every marker a second after the selection dismissed
  # them. The bounds are still recorded, so the next typed search is scoped to
  # where the map now is.
  def handle_event("viewport_changed", %{"bbox" => [_w, _s, _e, _n] = bbox} = params, socket) do
    socket = assign(socket, viewport: bbox)

    # `search_results != []` is the dismissal test. Both `select_feature` and
    # `search_dismiss` leave the query in the box deliberately, so re-querying
    # on the query alone resurrected a list the user had just dismissed — the
    # fly-to defect one gesture later. A list on screen still refreshes.
    if params["programmatic"] != true and socket.assigns.search_results != [] and
         searchable?(socket.assigns.search_query) do
      {:noreply, run_search(socket, socket.assigns.search_query)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("search_move", %{"dir" => dir}, socket) when dir in [1, -1] do
    count = length(socket.assigns.search_results)

    {:noreply, assign(socket, search_active: move_active(socket.assigns.search_active, dir, count))}
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
     |> assign(search_results: [], search_active: -1, search_searched: false)
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
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, mode: mode)}
  end

  @impl true
  def handle_event("route", %{"from" => from, "to" => to} = params, socket) do
    mode = Map.get(params, "mode", socket.assigns.mode)
    socket = assign(socket, route_from: from, route_to: to, mode: mode)

    with {:ok, from_coords} <- Coord.parse_latlon(from),
         {:ok, to_coords} <- Coord.parse_latlon(to),
         {:ok, result} <- plan_route(mode, from_coords, to_coords, socket.assigns.route_options) do
      socket = assign(socket, upstream_status: result.upstream_status)

      case route_legs(result.features) do
        [_ | _] = legs ->
          {:noreply,
           socket
           |> assign(directions: result.features)
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
      :error ->
        {:noreply, put_flash(socket, :error, "Could not parse from/to as lat,lon")}

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
    value = "#{Coord.format(lat)},#{Coord.format(lon)}"
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
          {:no_region, []}

        names ->
          if Safe.call(fn -> RegionSelection.pending_change?() end, true) do
            {Safe.call(fn -> RegionApplier.start(names) end), names}
          else
            # Selection unchanged since the last apply — only tools to do.
            {:no_region, []}
          end
      end

    socket = assign(socket, pending_services: %{}, service_status: refresh_service_status())

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
  def handle_params(params, _uri, socket) do
    socket = assign(socket, url_params: Map.drop(params, ["q"]))
    q = Map.get(params, "q", "")

    # The dead render is a throwaway that the connected mount immediately
    # replaces, so searching there bought nothing and cost a second Photon
    # round trip for every visit to a shared ?q= link.
    if q == socket.assigns.search_query or not connected?(socket) do
      {:noreply, assign(socket, search_query: q)}
    else
      {:noreply, run_search(socket, q)}
    end
  end

  @impl true
  def handle_info(:status_changed, socket) do
    {:noreply, assign(socket, service_status: refresh_service_status())}
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

  def handle_info(_other, socket), do: {:noreply, socket}

  # Rails used the same two-character floor: one letter matches most of the
  # planet, so it costs a Photon round trip per keystroke to return noise.
  @min_query_length 2

  # 40, not 8: the list is scoped to the viewport, so a brand search wants every
  # visible branch rather than the global top handful.
  @search_limit 40

  # Keeps whatever else is in the URL (a `tab`, say) and drops `q` entirely when
  # the box is empty, so a cleared search leaves `/` rather than `/?q=`.
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
    if searchable?(q) do
      dispatch_search(socket, q)
    else
      # The markers go with the list. Escape cleared them; backspacing did not,
      # so emptying the box left every pin stranded on the map.
      socket
      |> assign(
        search_query: q,
        search_results: [],
        search_active: -1,
        search_searched: false
      )
      |> push_results([])
    end
  end

  defp dispatch_search(socket, q) do
    params = %{
      query: String.trim(q),
      limit: @search_limit,
      lang: nil,
      lat: nil,
      lon: nil,
      bbox: socket.assigns.viewport
    }

    case Maps.Search.autocomplete(params) do
      {:ok, result} ->
        socket
        |> assign(
          search_query: q,
          search_results: result.features,
          search_status: result.upstream_status,
          upstream_status: result.upstream_status,
          search_active: -1,
          search_searched: true
        )
        |> push_results(result.features)

      {:error, _e} ->
        socket
        |> assign(
          search_query: q,
          search_results: [],
          search_status: "unavailable",
          upstream_status: "unavailable",
          search_active: -1,
          search_searched: true
        )
        |> push_results([])
    end
  end

  # One event replaces the whole marker set, mirroring the Rails map: every
  # result is a pin, so you can see where the matches are before choosing one.
  # Replacing wholesale also removes the clear-then-add ordering that let a
  # pan-triggered refresh wipe the pin a user had just dropped.
  defp push_results(socket, features) do
    push_event(socket, "map:set_results", %{points: SearchMarkers.points(features)})
  end

  defp select_feature(socket, feature) do
    coords = feature.coords

    socket
    |> assign(
      search_query: feature.label || "",
      search_results: [],
      search_active: -1,
      # Not `searched: true` with an empty list: the list is dismissed, not
      # empty, and the panel must not answer a chosen result with "No results".
      search_searched: false
    )
    |> push_event("map:fly_to", %{lat: coords.lat, lon: coords.lon, zoom: 14})
    |> push_results([feature])
    |> then(&push_patch(&1, to: search_path(&1, feature.label || ""), replace: true))
  end

  # Wraps at both ends, matching the Rails list. `-1` means "nothing highlighted"
  # and needs its own clauses rather than arithmetic: `Integer.mod(-1 + -1, 3)`
  # is 1, but ArrowUp from nothing must land on the last row.
  defp move_active(_current, _dir, 0), do: -1
  defp move_active(-1, 1, _count), do: 0
  defp move_active(-1, -1, count), do: count - 1
  defp move_active(current, dir, count), do: Integer.mod(current + dir, count)

  # Transit goes to OTP; everything else (auto/bicycle/pedestrian) to Valhalla.
  # Valhalla.route/2 raises on an unknown costing, so transit must never reach it.
  defp plan_route("transit", from, to, _options) do
    Maps.Transit.plan(from: from, to: to)
  end

  defp plan_route(mode, from, to, options) do
    Maps.Route.plan(from: from, to: to, mode: mode, options: costing_options(options))
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

  # Valhalla results carry a flat `legs` list; OTP transit results carry
  # `itineraries`, each with its own `legs`. Draw the first itinerary.
  defp route_legs(%{legs: legs}) when is_list(legs), do: legs

  defp route_legs(%{itineraries: [itinerary | _]}) when is_map(itinerary),
    do: Map.get(itinerary, :legs, [])

  defp route_legs(_), do: []

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

    <div class="fixed inset-0 p-2 sm:p-3 bg-base-200 flex gap-2 sm:gap-3">
      <AtlasWeb.SidePanel.side_panel
        active_tab={@active_tab}
        search_query={@search_query}
        search_results={@search_results}
        search_status={@search_status}
        search_active={@search_active}
        search_searched={@search_searched}
        directions={@directions}
        mode={@mode}
        route_from={@route_from}
        route_to={@route_to}
        route_options={@route_options}
        places={@places}
        tiles_url={@tiles_url}
        theme={@theme}
        service_status={@service_status}
        pending_services={@pending_services}
        tiles_download={@tiles_download}
        basemap_confirm={@basemap_confirm}
        timeline={@timeline}
      />

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

    <AtlasWeb.Settings.LogsModal.logs_modal
      :if={@service_logs}
      name={@service_logs.name}
      snapshot={@service_status[@service_logs.name]}
      logs={@service_logs}
    />
    """
  end
end
