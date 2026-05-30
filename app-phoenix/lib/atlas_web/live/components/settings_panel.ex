defmodule AtlasWeb.SettingsPanel do
  use AtlasWeb, :live_component

  alias Atlas.Control.{RegionCatalog, RegionSelection, Seeder}
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
     |> assign(:themes, @themes)}
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
      <div class="px-4 pt-3">
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
              <span class="text-base-content/60">Theme</span>
              <span class="font-mono text-[10px] truncate text-right">{@theme}</span>
            </div>
          </div>

          <form phx-submit="save_settings" class="flex flex-col gap-2 mt-2">
            <input
              type="text"
              name="tiles_url"
              value={@tiles_url}
              placeholder="Custom style or pmtiles URL…"
              class="input input-bordered input-xs w-full"
            />
            <div class="flex items-center gap-2">
              <label class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 flex-shrink-0">
                Theme
              </label>
              <select name="theme" class="select select-bordered select-xs flex-1">
                <option :for={t <- @themes} value={t} selected={@theme == t}>
                  {theme_label(t)}
                </option>
              </select>
            </div>
            <button type="submit" class="btn btn-primary btn-xs mt-1">Save basemap</button>
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
                <ul class="flex flex-col gap-1 text-xs">
                  <li
                    :for={svc <- list}
                    class="group relative pl-3 pr-2 py-1.5 rounded-md hover:bg-base-200/40 flex items-center gap-2"
                  >
                    <span class={"absolute left-0 top-0 bottom-0 w-1 rounded-l-md " <>
                      status_bar_class(@service_status[svc.name])}></span>
                    <span class="font-mono text-sm flex-1 min-w-0 truncate">{svc.name}</span>
                    <span class={"badge badge-sm " <> badge_class(@service_status[svc.name])}>
                      {status_label(@service_status[svc.name])}
                    </span>
                  </li>
                </ul>
              <% end %>
            <% end %>
          </div>
        </section>
      </div>

      <footer class="border-t border-base-300 p-4">
        <button type="button" class="btn btn-primary btn-block btn-sm" disabled>
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
