defmodule AtlasWeb.PlacesCard do
  use AtlasWeb, :live_component

  alias Atlas.Maps.Poi.Catalog

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:filter, fn -> "" end)
     |> assign(:sections, Catalog.sections())
     |> assign(:pinned, Catalog.pinned())}
  end

  @impl true
  def handle_event("filter_changed", %{"q" => q}, socket) do
    {:noreply, assign(socket, :filter, q)}
  end

  def handle_event("clear_filter", _params, socket) do
    {:noreply, assign(socket, :filter, "")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <header class="px-4 pt-4 pb-3 border-b border-base-200 flex items-end justify-between gap-3">
        <div>
          <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-primary/80">
            POIs &amp; categories
          </div>
          <h2 class="text-base font-semibold leading-tight mt-0.5 font-display">Places</h2>
        </div>
        <button type="button" phx-click="places_clear" class="btn btn-xs btn-ghost">Clear</button>
      </header>

      <%!-- Filter across all categories --%>
      <div class="px-4 pt-3 pb-2">
        <div class="relative">
          <span class="absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40 pointer-events-none">
            {icon("search", class: "w-4 h-4")}
          </span>
          <form phx-change="filter_changed" phx-target={@myself}>
            <input
              type="search"
              name="q"
              value={@filter}
              placeholder="Filter categories…"
              autocomplete="off"
              spellcheck="false"
              class="input input-bordered input-sm w-full pl-9 pr-9"
            />
          </form>
          <button
            type="button"
            phx-click="clear_filter"
            phx-target={@myself}
            class="absolute right-2 top-1/2 -translate-y-1/2 btn btn-square btn-ghost btn-xs"
            aria-label="Clear filter"
          >
            {icon("x", class: "w-3 h-3")}
          </button>
        </div>
      </div>

      <%!-- Quick picks — pinned tier from Catalog --%>
      <div class="px-4 pb-2">
        <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 mb-1.5">
          Quick picks
        </div>
        <div class="grid grid-cols-2 gap-1">
          <button
            :for={item <- @pinned}
            type="button"
            class="btn btn-sm btn-ghost justify-start gap-2"
            title={item.selector}
          >
            {icon("map-pin", class: "w-3.5 h-3.5")} {item.label}
          </button>
        </div>
      </div>

      <%!-- Accordion sections --%>
      <div class="px-2 border-t border-base-200 max-h-[40vh] overflow-y-auto">
        <details
          :for={section <- filtered_sections(@sections, @filter)}
          class="border-b border-base-200/60 last:border-b-0"
        >
          <summary class="cursor-pointer select-none flex items-center justify-between px-2 py-2 hover:bg-base-200/40 rounded-md">
            <span class="font-medium text-sm">{section.label}</span>
            <span class="font-mono text-[10px] text-base-content/50 tabular-nums">
              {length(section.items)}
            </span>
          </summary>
          <ul class="pl-3 pb-2 flex flex-col gap-0.5">
            <li :for={item <- visible_items(section.items, @filter)}>
              <button
                type="button"
                class="w-full flex items-center gap-2 text-left text-xs px-2 py-1.5 rounded hover:bg-base-200/40"
                title={item.selector}
              >
                {icon("map-pin", class: "w-3 h-3 text-base-content/40")} {item.label}
              </button>
            </li>
          </ul>
        </details>
      </div>

      <%!-- Results / empty state --%>
      <div class="flex-1 min-h-0 overflow-y-auto px-4 py-2 border-t border-base-200">
        <p :if={@places == []} class="text-xs text-base-content/60">
          No places loaded yet.
        </p>
        <ul :if={@places != []} class="flex flex-col gap-0.5">
          <li :for={place <- @places} class="flex items-start gap-2 p-2 rounded-md hover:bg-base-200">
            <span class="text-base-content/40 mt-0.5">
              {icon("map-pin", class: "w-4 h-4")}
            </span>
            <span class="text-sm leading-tight">{place.label}</span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp filtered_sections(sections, ""), do: sections

  defp filtered_sections(sections, filter) do
    needle = String.downcase(filter)

    sections
    |> Enum.filter(fn section ->
      String.contains?(String.downcase(section.label), needle) or
        Enum.any?(section.items, &item_matches?(&1, needle))
    end)
  end

  defp visible_items(items, ""), do: items

  defp visible_items(items, filter) do
    needle = String.downcase(filter)
    Enum.filter(items, &item_matches?(&1, needle))
  end

  defp item_matches?(item, needle) do
    String.contains?(String.downcase(item.label), needle) or
      String.contains?(String.downcase(item.selector), needle)
  end
end
