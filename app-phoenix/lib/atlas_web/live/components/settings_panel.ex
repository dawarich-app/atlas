defmodule AtlasWeb.SettingsPanel do
  @moduledoc """
  Live component hosting the settings drawer and its tab bar.
  """

  use AtlasWeb, :live_component

  alias Atlas.Control.{Preflight, RegionCatalog, RegionSelection, Seeder, ServiceFormatting}
  alias Atlas.Maps.BasemapPresets
  alias Atlas.Repo
  alias AtlasWeb.Settings

  @themes ~w(light dark grayscale white black forest-patina bunker-brutalist atlas-light atlas-dark)
  @profiles ~w(geocoding routing pois transit data-setup)

  @impl true
  def update(assigns, socket) do
    regions_result = Map.get_lazy(socket.assigns, :catalog_result, &safe_regions/0)
    selection_result = safe_selection()

    tree_result =
      if regions_result == :unavailable,
        do: :unavailable,
        else: RegionCatalog.index(regions_result)

    control_ready =
      regions_result != :unavailable and selection_result != :unavailable and
        tree_result != :unavailable

    regions = if regions_result == :unavailable, do: [], else: regions_result
    selection = if selection_result == :unavailable, do: [], else: selection_result
    tree_index = if tree_result == :unavailable, do: %{}, else: tree_result

    known = Seeder.known_services()
    by_name = Map.new(regions, &{&1.name, &1})

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:transit_switching, fn -> nil end)
     |> assign_new(:pending_services, fn -> %{} end)
     |> assign_new(:tiles_download, fn -> nil end)
     |> assign_new(:timeline, fn -> nil end)
     |> assign_new(:basemap_confirm, fn -> nil end)
     |> assign_new(:region_query, fn -> "" end)
     |> assign_new(:expanded, fn -> MapSet.new() end)
     |> assign_new(:settings_tab, fn -> "region" end)
     |> assign_new(:open_cats, fn -> MapSet.new(@profiles) end)
     |> assign_new(:open_upd, fn -> MapSet.new() end)
     |> assign_new(:info_for, fn -> nil end)
     |> maybe_cache_catalog(regions_result)
     |> assign(:regions, regions)
     |> assign(:tree_index, tree_index)
     |> assign(:by_name, by_name)
     |> assign(:region_selection, selection)
     |> assign(:control_ready, control_ready)
     |> assign(:known_services, known)
     |> assign(:quick_picks, quick_picks(regions))
     |> assign(:themes, @themes)
     |> assign(:basemap_presets, BasemapPresets.all())
     |> assign(:preflight_failures, preflight_failures())
     |> assign_pending(selection)}
  end

  defp preflight_failures do
    Preflight.results() |> Preflight.failures()
  rescue
    _ -> []
  end

  defp assign_pending(socket, selection) do
    pending = socket.assigns.pending_services
    enable = pending |> Enum.filter(fn {_n, d} -> d end) |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    disable =
      pending |> Enum.filter(fn {_n, d} -> !d end) |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    region_names = active_region_names(selection)
    applied = applied_region_names()
    region_changed = Enum.sort(region_names) != Enum.sort(applied)
    pending_region_names = if region_changed, do: region_names, else: []

    socket
    |> assign(:pending_enable, enable)
    |> assign(:pending_disable, disable)
    |> assign(:pending_region_names, pending_region_names)
    |> assign(:region_changed, region_changed)
    |> assign(:applied_region_names, applied)
    |> assign(:pending_count, map_size(pending) + if(region_changed, do: 1, else: 0))
  end

  defp maybe_cache_catalog(socket, :unavailable), do: socket
  defp maybe_cache_catalog(socket, regions), do: assign(socket, :catalog_result, regions)

  defp active_region_names(selection) when is_list(selection) do
    selection |> Enum.filter(& &1.active) |> Enum.map(& &1.region_name)
  end

  defp active_region_names(_), do: []

  @impl true
  def handle_event("settings_tab", %{"tab" => tab}, socket)
      when tab in ~w(region basemap services) do
    {:noreply, assign(socket, :settings_tab, tab)}
  end

  def handle_event("region_search", %{"q" => q}, socket) do
    {:noreply, assign(socket, :region_query, q)}
  end

  def handle_event("toggle_node", %{"name" => name}, socket) do
    {:noreply, assign(socket, :expanded, toggle_member(socket.assigns.expanded, name))}
  end

  def handle_event("toggle_cat", %{"cat" => cat}, socket) do
    {:noreply, assign(socket, :open_cats, toggle_member(socket.assigns.open_cats, cat))}
  end

  def handle_event("toggle_upd", %{"name" => name}, socket) do
    {:noreply, assign(socket, :open_upd, toggle_member(socket.assigns.open_upd, name))}
  end

  def handle_event("toggle_info", %{"name" => name}, socket) do
    next = if socket.assigns.info_for == name, do: nil, else: name
    {:noreply, assign(socket, :info_for, next)}
  end

  def handle_event("preflight_recheck", _params, socket) do
    failures =
      try do
        Preflight.refresh() |> Preflight.failures()
      rescue
        _ -> []
      end

    {:noreply, assign(socket, :preflight_failures, failures)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative mx-auto flex h-full w-full max-w-4xl flex-col">
      <header class="shrink-0 px-4 pt-4 pb-3">
        <div class="flex items-center justify-between gap-3">
          <h2 class="font-display text-3xl font-extrabold leading-none tracking-tight">Settings</h2>
          <button type="button" phx-click="back_to_map" class="btn btn-ghost btn-sm">
            Back to map
          </button>
        </div>
        <p class="mt-2 text-sm text-base-content/65">Manage your regions, map appearance and services.</p>
        <div class="mt-4 flex flex-wrap gap-x-4 gap-y-1 text-sm" aria-label="Service overview">
          <span class="font-semibold text-primary">{ready_known(@service_status, @known_services)} running</span>
          <span>{off_known(@service_status, @known_services)} off</span>
          <span :if={pending_known(@service_status, @known_services) > 0} class="text-warning">
            {pending_known(@service_status, @known_services)} need attention or are starting
          </span>
          <span class="text-base-content/65">{disk_summary(@service_status)}</span>
        </div>
        <.link navigate={~p"/setup"} class="btn btn-outline btn-sm mt-3">Setup wizard</.link>
        <.link navigate={~p"/transport-data"} class="btn btn-outline btn-sm mt-3">Transport data</.link>
        <nav class="mt-4 flex flex-wrap gap-2" aria-label="Settings sections">
          <.tab_pill :for={{id, lbl} <- tabs()} id={id} label={lbl} active={@settings_tab} target={@myself} />
        </nav>
      </header>

      <div class="flex flex-1 min-h-0 flex-col overflow-hidden px-4">
        <div
          :if={@preflight_failures != []}
          class="mb-4 rounded-2xl bg-error/10 px-4 py-3.5"
          data-role="preflight-banner"
        >
          <div class="flex items-center font-mono text-[12px] font-semibold uppercase tracking-[0.08em] text-error">
            Control plane degraded
            <button
              type="button"
              phx-click="preflight_recheck"
              phx-target={@myself}
              class="ml-auto normal-case tracking-normal font-sans text-[12.5px] font-semibold text-base-content/60"
            >
              re-check
            </button>
          </div>
          <div :for={f <- @preflight_failures} class="mt-2.5 text-[13px] leading-relaxed">
            <div class="font-semibold">{preflight_title(f.check)}</div>
            <div :if={f.detail} class="mt-0.5 break-words font-mono text-[11.5px] text-base-content/60">
              {f.detail}
            </div>
            <div :if={f.remedy} class="mt-0.5 text-base-content/75">{f.remedy}</div>
          </div>
        </div>

        <div
          :if={!@control_ready}
          class="rounded-2xl bg-base-200/60 px-4 py-5 text-sm text-base-content/70"
          data-role="control-starting"
        >
          <span class="loading loading-spinner loading-xs mr-2"></span>
          Control plane is starting — settings will load in a moment.
        </div>

        <div id="settings-tab-region" class={[@settings_tab == "region" && "atlas-fade", panel_class(@settings_tab, "region")]}>
          <div class="mb-4 rounded-2xl bg-base-100/60 p-4 text-sm">
            <p class="font-semibold">Last applied selection</p>
            <p class="mt-1">{region_names_label(@applied_region_names, @by_name)}</p>
            <p class="mt-2 text-base-content/65">This records the last submitted setup. Dataset coverage and installation status can differ by service.</p>
          </div>
          <Settings.RegionTab.region_tab
            regions={@regions}
            timeline={@timeline}
            tree_index={@tree_index}
            by_name={@by_name}
            selection={@region_selection}
            region_query={@region_query}
            expanded={@expanded}
            quick_picks={@quick_picks}
            myself={@myself}
          />
        </div>
        <div id="settings-tab-basemap" class={[@settings_tab == "basemap" && "atlas-fade", panel_class(@settings_tab, "basemap")]}>
          <Settings.BasemapTab.basemap_tab
            presets={@basemap_presets}
            tiles_url={@tiles_url}
            tiles_download={@tiles_download}
            basemap_confirm={@basemap_confirm}
            themes={@themes}
            theme={@theme}
          />
        </div>
        <div id="settings-tab-services" class={[@settings_tab == "services" && "atlas-fade", panel_class(@settings_tab, "services")]}>
          <Settings.ServicesTab.services_tab
            known_services={@known_services}
            service_status={@service_status}
            pending_services={@pending_services}
            transit_switching={@transit_switching}
            open_cats={@open_cats}
            open_upd={@open_upd}
            info_for={@info_for}
            myself={@myself}
          />
        </div>
      </div>

      <footer :if={@settings_tab != "basemap"} class="shrink-0 border-t border-base-300 p-4">
        <div class="max-h-[25vh] overflow-y-auto" aria-live="polite">
        <Settings.PendingSummary.pending_summary
          :if={@pending_count > 0}
          enable={@pending_enable}
          disable={@pending_disable}
          region_names={@pending_region_names}
          region_changed={@region_changed}
          previous_region_names={@applied_region_names}
          by_name={@by_name}
          pending_services={@pending_services}
        />
        </div>
        <p :if={@pending_count == 0} class="mb-3 text-sm text-base-content/65">No pending changes.</p>
        <div class="flex flex-wrap gap-2">
        <button :if={@pending_count > 0} type="button" phx-click="discard_settings_changes" class="btn btn-ghost">
          Discard changes
        </button>
        <button
          type="button"
          phx-click="apply_selection"
          disabled={@pending_count == 0}
          class={["btn flex-1", @pending_count == 0 && "btn-disabled", @pending_count > 0 && "btn-primary"]}
        >
          {apply_label(@pending_count)}
        </button>
        </div>
      </footer>
      <footer :if={@settings_tab == "basemap"} class="shrink-0 border-t border-base-300 p-4 text-sm text-base-content/65">
        Map appearance is saved immediately.
        <button :if={@pending_count > 0} type="button" phx-click="settings_tab" phx-value-tab="region" phx-target={@myself} class="mt-1 block font-semibold text-primary">
          Review {@pending_count} pending region or service changes
        </button>
      </footer>

    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :active, :string, required: true
  attr :target, :any, required: true

  defp tab_pill(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="settings_tab"
      aria-pressed={to_string(@active == @id)}
      aria-controls={"settings-tab-" <> @id}
      phx-value-tab={@id}
      phx-target={@target}
      class={[
        "rounded-xl px-5 py-2.5 text-[14.5px] font-bold transition",
        @active == @id && "bg-primary text-primary-content shadow-md shadow-primary/30",
        @active != @id && "bg-transparent text-base-content/55"
      ]}
    >
      {@label}
    </button>
    """
  end

  defp tabs, do: [{"region", "Region"}, {"basemap", "Basemap"}, {"services", "Services"}]

  defp apply_label(0), do: "Apply changes"
  defp apply_label(n), do: "Apply changes (#{n})"

  defp panel_class(active, tab) when active == tab,
    do: "block flex-1 min-h-0 overflow-y-auto pb-4"

  defp panel_class(_active, _tab), do: "hidden"

  defp ready_known(status_map, known) when is_map(status_map) do
    Enum.count(known, fn %{name: name} ->
      ServiceFormatting.running?(Map.get(status_map, name))
    end)
  end

  defp ready_known(_, _), do: 0

  defp off_known(status_map, known) do
    Enum.count(known, fn %{name: name} ->
      snapshot = Map.get(status_map, name)

      not ServiceFormatting.running?(snapshot) and
        not ServiceFormatting.installing?(snapshot) and
        not ServiceFormatting.enabled?(snapshot) and
        not match?(%{status: status} when status in [:error, :unhealthy], snapshot)
    end)
  end

  defp pending_known(status_map, known),
    do: length(known) - ready_known(status_map, known) - off_known(status_map, known)

  defp disk_summary(status_map) do
    case ServiceFormatting.total_disk_label(status_map) do
      "—" -> "Storage usage unavailable"
      label -> "Reported storage: #{label}"
    end
  end

  defp applied_region_names do
    RegionSelection.applied_names()
  rescue
    _ -> []
  end

  defp toggle_member(set, key) do
    if MapSet.member?(set, key), do: MapSet.delete(set, key), else: MapSet.put(set, key)
  end

  defp quick_picks(regions) do
    regions
    |> Enum.filter(fn r -> is_nil(r.parent) and (r.kind == "continent" or r.name == "planet") end)
    |> Enum.sort_by(&{&1.name != "planet", &1.label})
    |> Enum.take(6)
  end

  defp region_names_label([], _by_name), do: "No selection recorded"

  defp region_names_label(names, by_name),
    do: Enum.map_join(names, ", ", &catalog_label(by_name, &1))

  defp catalog_label(by_name, name) do
    case Map.get(by_name, name) do
      %{label: label} when is_binary(label) and label != "" -> label
      _ -> name
    end
  end

  defp preflight_title(:docker_cli), do: "Docker CLI missing"
  defp preflight_title(:compose), do: "docker compose unavailable"
  defp preflight_title(:socket), do: "Docker socket unreachable"
  defp preflight_title(:data_dirs), do: "Data directories not writable"
  defp preflight_title(:osmium), do: "osmium-tool missing"
  defp preflight_title(other), do: to_string(other)

  # `:unavailable` (instead of a silently empty list) lets the panel render a
  # "control plane starting" placeholder rather than lying with "region: none"
  # during the boot race.
  defp safe_regions do
    RegionCatalog.all()
  rescue
    _ -> :unavailable
  end

  defp safe_selection do
    import Ecto.Query

    Repo.all(from r in RegionSelection, order_by: [asc: r.position])
  rescue
    _ -> :unavailable
  end
end
