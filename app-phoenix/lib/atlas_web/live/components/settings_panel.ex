defmodule AtlasWeb.SettingsPanel do
  use AtlasWeb, :live_component

  alias Atlas.Control.{RegionCatalog, RegionSelection, Seeder}
  alias Atlas.Maps.BasemapPresets
  alias Atlas.Repo

  @themes ~w(light dark grayscale white black forest-patina bunker-brutalist atlas-light atlas-dark)

  @impl true
  def update(assigns, socket) do
    regions = safe_regions()
    selection = safe_selection()
    known = Seeder.known_services()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:regions, regions)
     |> assign(:region_selection, selection)
     |> assign(:known_services, known)
     |> assign(:themes, @themes)
     |> assign(:basemap_presets, BasemapPresets.all())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <header class="px-4 pt-4 pb-3 border-b border-base-200">
        <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-primary/80">
          Control plane
        </div>
        <h2 class="text-base font-semibold leading-tight mt-0.5 font-display">Settings</h2>
      </header>

      <%!-- At-a-glance stats strip --%>
      <div class="px-4">
        <div class="grid grid-cols-3 gap-2 rounded-md bg-base-200/40 p-2">
          <div class="text-center">
            <div class="text-lg font-semibold tabular-nums">
              {ready_count(@service_status)}<span class="text-base-content/40">/{length(@known_services)}</span>
            </div>
            <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55">
              Ready
            </div>
          </div>
          <div class="text-center">
            <div class="text-lg font-semibold tabular-nums">—</div>
            <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55">
              Disk
            </div>
          </div>
          <div class="text-center">
            <div class="text-lg font-semibold truncate">{active_region_label(@region_selection)}</div>
            <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55">
              Region
            </div>
          </div>
        </div>
      </div>

      <div class="flex-1 min-h-0 overflow-y-auto px-4 py-3 flex flex-col gap-4">
        <%!-- Region section --%>
        <section>
          <h3 class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 mb-2 flex items-center gap-2">
            {icon("map-pin", class: "w-3 h-3")} Region
          </h3>
          <div :if={@regions == []} class="text-xs text-base-content/60">
            No region presets found.
          </div>
          <div :if={@regions != []} class="grid grid-cols-2 gap-2">
            <label
              :for={region <- @regions}
              class={"flex items-center gap-2 px-3 py-2 rounded-md border cursor-pointer transition-colors " <>
                if(region_selected?(region, @region_selection),
                  do: "border-primary bg-primary/10",
                  else: "border-base-300 hover:bg-base-200/60")}
            >
              <input
                type="checkbox"
                name="regions[]"
                value={region.name}
                phx-click="toggle_region"
                phx-value-name={region.name}
                class="checkbox checkbox-xs checkbox-primary"
                checked={region_selected?(region, @region_selection)}
              />
              <span class="flex-1 min-w-0">
                <span class="block font-medium text-sm truncate">{region.label}</span>
                <span class="block font-mono text-[10px] text-base-content/55 tabular-nums">
                  {size_hint(region.name)}
                </span>
              </span>
            </label>
          </div>
        </section>

        <%!-- Basemap section --%>
        <section>
          <h3 class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 mb-2 flex items-center gap-2">
            {icon("map", class: "w-3 h-3")} Basemap
          </h3>

          <div class="bg-base-200/40 rounded-md p-2.5 text-xs flex flex-col gap-1.5">
            <div class="flex items-baseline justify-between gap-2">
              <span class="text-base-content/60">In use</span>
              <span class="font-mono text-[10px] truncate text-right">{@tiles_url || "—"}</span>
            </div>
            <div class="flex items-baseline justify-between gap-2">
              <span class="text-base-content/60">Local file</span>
              <span class="text-[10px] tabular-nums text-right">—</span>
            </div>
            <div class="flex items-baseline justify-between gap-2">
              <span class="text-base-content/60">.env default</span>
              <span class="font-mono text-[10px] truncate text-right text-base-content/50">—</span>
            </div>
          </div>

          <%!-- Basemap preset cards (parity with Rails basemap_controller.js PRESETS) --%>
          <div class="grid grid-cols-1 gap-2 mt-2">
            <div
              :for={preset <- @basemap_presets}
              class="border border-base-300 rounded-md p-2 flex flex-col gap-1.5"
            >
              <div class="text-sm font-medium leading-tight">{preset.label}</div>
              <div class="text-[10px] text-base-content/60 leading-snug">{preset.note}</div>
              <button
                type="button"
                phx-click="use_basemap"
                phx-value-id={preset.id}
                class="btn btn-xs btn-primary mt-1 self-start"
                disabled={preset.download && @tiles_download && @tiles_download.status == :running}
              >
                {if preset.download, do: "Download & use", else: "Use"}
              </button>

              <%!-- Download progress for download: true presets (parity with Rails progress block) --%>
              <div
                :if={preset.download && @tiles_download}
                class="mt-1 flex flex-col gap-1"
              >
                <div class="flex items-center justify-between text-[10px] font-mono uppercase tracking-wider">
                  <span class={[
                    "px-1.5 py-0.5 rounded",
                    @tiles_download.status == :running && "bg-warning/30",
                    @tiles_download.status == :done && "bg-success/30",
                    @tiles_download.status == :error && "bg-error/30"
                  ]}>
                    {Phoenix.Naming.humanize(to_string(@tiles_download.status))}
                  </span>
                  <span :if={@tiles_download[:progress]} class="text-base-content/60">
                    {Float.round((@tiles_download[:progress] || 0.0) * 100, 1)}%
                  </span>
                </div>
                <progress
                  :if={@tiles_download.status == :running}
                  class="progress progress-primary h-1"
                  value={@tiles_download[:progress] || 0}
                  max="1"
                ></progress>
                <p :if={@tiles_download[:reason]} class="text-[10px] text-error-content/80">
                  {@tiles_download.reason}
                </p>
              </div>
            </div>
          </div>

          <form
            phx-submit="save_settings"
            class="flex gap-1 mt-2"
          >
            <input
              type="text"
              name="tiles_url"
              value={@tiles_url}
              placeholder="Custom style or pmtiles URL…"
              class="input input-bordered input-xs w-full"
            />
            <input type="hidden" name="theme" value={@theme} />
            <button type="submit" class="btn btn-xs btn-primary">Use</button>
          </form>

          <div class="flex gap-1 mt-2">
            <button
              type="button"
              phx-click="use_local_tiles"
              class="btn btn-xs btn-ghost flex-1"
            >
              Use local file
            </button>
            <button
              type="button"
              phx-click="use_env_tiles"
              class="btn btn-xs btn-ghost flex-1"
            >
              Use .env default
            </button>
          </div>

          <form phx-change="update_theme" class="flex items-center gap-2 mt-2">
            <label class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 flex-shrink-0">
              Theme
            </label>
            <select name="theme" class="select select-bordered select-xs flex-1">
              <option :for={t <- @themes} value={t} selected={@theme == t}>
                {theme_label(t)}
              </option>
            </select>
          </form>
        </section>

        <%!-- Services section --%>
        <section>
          <h3 class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 mb-2 flex items-center gap-2">
            {icon("server", class: "w-3 h-3")} Services
          </h3>
          <div class="flex flex-col">
            <%= for {profile, label} <- profile_order() do %>
              <% list = services_in_profile(@known_services, profile) %>
              <%= if list != [] do %>
                <h4 class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/45 mt-3 first:mt-0 mb-1 pl-3">
                  {label}
                </h4>
                <div :for={svc <- list} class="group relative pl-3 pr-2 py-2 rounded-md hover:bg-base-200/40 transition-colors">
                  <span class={"absolute left-0 top-0 bottom-0 w-1 rounded-l-md " <>
                    status_bar_class(@service_status[svc.name])}></span>

                  <div class="flex items-center gap-2">
                    <span class="font-mono text-sm flex-1 min-w-0 truncate flex items-center gap-1.5">
                      {svc.name}
                      <button
                        type="button"
                        class="text-base-content/40 hover:text-base-content/80 cursor-pointer inline-flex focus:outline-none focus:text-base-content/80 shrink-0"
                        aria-label={"About " <> svc.name}
                      >
                        {icon("info", class: "w-3.5 h-3.5")}
                      </button>
                      <button
                        type="button"
                        class="text-base-content/40 hover:text-base-content/80 cursor-pointer inline-flex focus:outline-none focus:text-base-content/80 shrink-0"
                        aria-label={"View logs for " <> svc.name}
                        title="Logs"
                      >
                        {icon("scroll-text", class: "w-3.5 h-3.5")}
                      </button>
                    </span>
                    <span class={"badge badge-sm " <> badge_class(@service_status[svc.name])}>
                      {status_label(@service_status[svc.name])}
                    </span>
                    <span class="text-xs text-base-content/30 tabular-nums w-16 text-right">—</span>
                    <label class="cursor-pointer shrink-0 flex flex-col items-end gap-0.5">
                      <input
                        type="checkbox"
                        class="toggle toggle-sm toggle-primary"
                        phx-click="toggle_service"
                        phx-value-name={svc.name}
                        checked={service_enabled?(@service_status[svc.name])}
                      />
                    </label>
                  </div>

                  <%!-- Dataset auto-update controls (stubbed for parity) --%>
                  <details class="mt-2 border-t border-base-200 pt-2">
                    <summary class="cursor-pointer select-none flex items-center justify-between gap-2 list-none text-xs">
                      <span class="flex items-center gap-1.5 text-base-content/70">
                        {icon("refresh-cw", class: "w-3 h-3")}
                        <span class="font-mono uppercase tracking-[0.14em] text-[10px]">Updates</span>
                      </span>
                      <span class="text-[10px] text-base-content/50 tabular-nums">—</span>
                    </summary>

                    <div class="mt-2 pl-1 grid grid-cols-1 gap-2 text-xs">
                      <label class="flex items-center gap-2 cursor-pointer">
                        <input
                          type="checkbox"
                          class="toggle toggle-xs toggle-primary"
                          phx-click="toggle_auto"
                          phx-value-name={svc.name}
                        />
                        <span class="text-[11px]">Auto-update</span>
                      </label>

                      <form phx-submit="save_schedule" class="flex items-center gap-2">
                        <input type="hidden" name="name" value={svc.name} />
                        <span class="font-mono uppercase tracking-[0.14em] text-[10px] text-base-content/40 shrink-0">
                          Cron
                        </span>
                        <input
                          type="text"
                          name="cron"
                          placeholder="0 3 * * *"
                          class="input input-bordered input-xs flex-1 font-mono text-[11px]"
                        />
                        <button type="submit" class="btn btn-xs btn-ghost">Save</button>
                      </form>

                      <button
                        type="button"
                        phx-click="update_now"
                        phx-value-name={svc.name}
                        class="btn btn-xs btn-outline btn-primary w-full"
                      >
                        {icon("refresh-cw", class: "w-3 h-3")} <span>Update now</span>
                      </button>
                    </div>
                  </details>
                </div>
              <% end %>
            <% end %>
          </div>
        </section>
      </div>

      <footer class="border-t border-base-300 p-4">
        <button
          type="button"
          phx-click="apply_selection"
          class="btn btn-primary btn-block btn-sm"
        >
          Save &amp; apply selection
        </button>
      </footer>
    </div>
    """
  end

  defp profile_order do
    [
      {"geocoding", "Geocoding"},
      {"routing", "Routing"},
      {"pois", "POIs"},
      {"transit", "Transit"},
      {"data-setup", "Data setup"}
    ]
  end

  defp services_in_profile(services, profile) do
    services
    |> Enum.filter(&(&1.profile == profile))
    |> Enum.sort_by(& &1.name)
  end

  defp ready_count(status_map) when is_map(status_map) do
    Enum.count(status_map, fn {_name, snap} -> match?(%{status: :ready}, snap) end)
  end

  defp ready_count(_), do: 0

  defp service_enabled?(%{status: status}) when status in [:ready, :starting, :downloading, :building], do: true
  defp service_enabled?(_), do: false

  defp status_label(nil), do: "—"
  defp status_label(%{status: status}) when is_atom(status), do: Atom.to_string(status)
  defp status_label(%{status: status}) when is_binary(status), do: status
  defp status_label(_), do: "—"

  defp status_bar_class(%{status: :ready}), do: "bg-success"
  defp status_bar_class(%{status: :starting}), do: "bg-warning animate-pulse"
  defp status_bar_class(%{status: :downloading}), do: "bg-warning animate-pulse"
  defp status_bar_class(%{status: :building}), do: "bg-warning animate-pulse"
  defp status_bar_class(%{status: :error}), do: "bg-error"
  defp status_bar_class(%{status: :unhealthy}), do: "bg-error"
  defp status_bar_class(%{status: :stopped}), do: "bg-base-300"
  defp status_bar_class(_), do: "bg-base-300/60"

  defp badge_class(%{status: :ready}), do: "badge-success"
  defp badge_class(%{status: :starting}), do: "badge-warning"
  defp badge_class(%{status: :downloading}), do: "badge-warning"
  defp badge_class(%{status: :building}), do: "badge-warning"
  defp badge_class(%{status: :error}), do: "badge-error"
  defp badge_class(%{status: :unhealthy}), do: "badge-error"
  defp badge_class(_), do: "badge-ghost"

  defp region_selected?(region, selection) when is_list(selection) do
    Enum.any?(selection, &(&1.region_name == region.name and &1.active))
  end

  defp region_selected?(_, _), do: false

  defp active_region_label([]), do: "None"

  defp active_region_label(selection) when is_list(selection) do
    case Enum.find(selection, & &1.active) do
      nil -> "None"
      %{region_name: name} -> name |> String.replace("-", " ") |> String.capitalize()
    end
  end

  defp active_region_label(_), do: "None"

  defp size_hint("planet"), do: "~1.1 TB"
  defp size_hint("europe"), do: "~460 GB"
  defp size_hint(name) when name in ~w(germany france italy), do: "~75 GB"

  defp size_hint(name) do
    if String.contains?(name, "multi"), do: "~25 GB", else: "~15 GB"
  end

  defp safe_regions do
    RegionCatalog.all()
  rescue
    _ -> []
  end

  defp safe_selection do
    import Ecto.Query

    Repo.all(from r in RegionSelection, order_by: [asc: r.position])
  rescue
    _ -> []
  end

  defp theme_label(t) do
    t
    |> String.replace("-", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
