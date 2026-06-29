defmodule AtlasWeb.MapLive do
  use AtlasWeb, :live_view

  alias Atlas.Geometry.Coord
  alias Atlas.Maps
  alias Atlas.Settings

  alias Atlas.Control.{
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
       service_logs: nil,
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

    with {:ok, from_coords} <- Coord.parse_latlon(from),
         {:ok, to_coords} <- Coord.parse_latlon(to),
         {:ok, result} <- Maps.Route.plan(from: from_coords, to: to_coords, mode: mode) do
      case result.features do
        %{legs: legs} when is_list(legs) and legs != [] ->
          {:noreply,
           socket
           |> assign(directions: result.features, upstream_status: result.upstream_status)
           |> push_event("map:draw_route", %{geojson: Coord.legs_to_geojson(legs)})}

        _ ->
          {:noreply,
           assign(socket, directions: result.features, upstream_status: result.upstream_status)}
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

  def handle_info({:apply_progress, progress}, socket) do
    case socket.assigns.apply_status do
      %{job_id: job_id} = status when job_id == progress.job_id ->
        {:noreply, assign(socket, apply_status: Map.merge(status, progress))}

      _ ->
        {:noreply, socket}
    end
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

  def handle_info(_other, socket), do: {:noreply, socket}

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
        apply_status={@apply_status}
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
