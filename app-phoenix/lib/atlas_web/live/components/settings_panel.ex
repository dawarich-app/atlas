defmodule AtlasWeb.SettingsPanel do
  use AtlasWeb, :live_component

  import AtlasWeb.Settings.Atoms

  alias Atlas.Control.{RegionCatalog, RegionSelection, Seeder, ServiceFormatting}
  alias Atlas.Maps.BasemapPresets
  alias Atlas.Repo
  alias AtlasWeb.Settings

  @themes ~w(light dark grayscale white black forest-patina bunker-brutalist atlas-light atlas-dark)
  @profiles ~w(geocoding routing pois transit data-setup)

  @impl true
  def update(assigns, socket) do
    regions_result = safe_regions()
    selection_result = safe_selection()
    tree_result = safe_tree_index()

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
     |> assign_new(:pending_services, fn -> %{} end)
     |> assign_new(:tiles_download, fn -> nil end)
     |> assign_new(:apply_status, fn -> nil end)
     |> assign_new(:basemap_confirm, fn -> nil end)
     |> assign_new(:region_query, fn -> "" end)
     |> assign_new(:expanded, fn -> MapSet.new() end)
     |> assign_new(:settings_tab, fn -> "region" end)
     |> assign_new(:open_cats, fn -> MapSet.new(@profiles) end)
     |> assign_new(:open_upd, fn -> MapSet.new() end)
     |> assign_new(:info_for, fn -> nil end)
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
    Atlas.Control.Preflight.results() |> Atlas.Control.Preflight.failures()
  rescue
    _ -> []
  end

  defp assign_pending(socket, selection) do
    pending = socket.assigns.pending_services
    enable = pending |> Enum.filter(fn {_n, d} -> d end) |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    disable =
      pending |> Enum.filter(fn {_n, d} -> !d end) |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    region_names = active_region_names(selection)
    region_changed = region_selection_changed?()
    pending_region_names = if region_changed, do: region_names, else: []

    socket
    |> assign(:pending_enable, enable)
    |> assign(:pending_disable, disable)
    |> assign(:pending_region_names, pending_region_names)
    |> assign(:pending_count, map_size(pending) + if(region_changed, do: 1, else: 0))
  end

  defp region_selection_changed? do
    RegionSelection.pending_change?()
  rescue
    _ -> false
  end

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
        Atlas.Control.Preflight.refresh() |> Atlas.Control.Preflight.failures()
      rescue
        _ -> []
      end

    {:noreply, assign(socket, :preflight_failures, failures)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative flex h-full flex-col">
      <header class="px-4 pt-4">
        <.eyebrow>Control plane</.eyebrow>
        <div class="mt-1 flex items-end gap-3.5">
          <h2 class="font-display text-3xl font-extrabold leading-none tracking-tight">Settings</h2>
          <div class="ml-auto flex items-center pb-0.5">
            <.mini_stat
              value={"#{ready_known(@service_status, @known_services)}/#{length(@known_services)}"}
              label="ready"
              flash={installing_any?(@service_status)}
            />
            <span class="mx-3.5 h-6 w-px bg-base-content/15"></span>
            <.mini_stat value={ServiceFormatting.total_disk_label(@service_status)} label="disk" />
            <span class="mx-3.5 h-6 w-px bg-base-content/15"></span>
            <.mini_stat
              value={
                if @control_ready,
                  do: active_region_label(@region_selection, @by_name),
                  else: "…"
              }
              label="region"
            />
          </div>
        </div>

        <div class="mt-4 flex gap-2">
          <.tab_pill :for={{id, lbl} <- tabs()} id={id} label={lbl} active={@settings_tab} target={@myself} />
        </div>
      </header>

      <div class="flex-1 min-h-0 overflow-y-auto px-4 py-4">
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
          <Settings.RegionTab.region_tab
            regions={@regions}
            apply_status={@apply_status}
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
            open_cats={@open_cats}
            open_upd={@open_upd}
            info_for={@info_for}
            myself={@myself}
          />
        </div>
      </div>

      <footer class="border-t border-base-300 p-4">
        <Settings.PendingSummary.pending_summary
          :if={@pending_enable != [] or @pending_disable != []}
          enable={@pending_enable}
          disable={@pending_disable}
          region_names={@pending_region_names}
          pending_services={@pending_services}
        />
        <button
          type="button"
          phx-click="apply_selection"
          disabled={@pending_count == 0}
          class={["btn btn-block", @pending_count == 0 && "btn-disabled", @pending_count > 0 && "btn-primary"]}
        >
          {apply_label(@pending_count)}
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

  defp apply_label(0), do: "Save & apply selection"
  defp apply_label(n), do: "Save & apply (#{n})"

  defp panel_class(active, tab) when active == tab, do: "block"
  defp panel_class(_active, _tab), do: "hidden"

  defp ready_known(status_map, known) when is_map(status_map) do
    Enum.count(known, fn %{name: name} ->
      ServiceFormatting.running?(Map.get(status_map, name))
    end)
  end

  defp ready_known(_, _), do: 0

  defp installing_any?(status_map) when is_map(status_map) do
    Enum.any?(status_map, fn {_n, snap} -> ServiceFormatting.installing?(snap) end)
  end

  defp installing_any?(_), do: false

  defp toggle_member(set, key) do
    if MapSet.member?(set, key), do: MapSet.delete(set, key), else: MapSet.put(set, key)
  end

  defp quick_picks(regions) do
    regions
    |> Enum.filter(fn r -> is_nil(r.parent) and (r.kind == "continent" or r.name == "planet") end)
    |> Enum.sort_by(&{&1.name != "planet", &1.label})
    |> Enum.take(6)
  end

  defp active_region_label(selection, by_name) when is_list(selection) do
    case Enum.filter(selection, & &1.active) do
      [] ->
        "none"

      [first | rest] ->
        label = catalog_label(by_name, first.region_name)
        if rest == [], do: label, else: "#{label} +#{length(rest)}"
    end
  end

  defp active_region_label(_, _), do: "none"

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

  defp safe_tree_index do
    RegionCatalog.tree_index()
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
