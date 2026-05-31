defmodule AtlasWeb.PlacesCard do
  use AtlasWeb, :live_component

  alias Atlas.Maps.Poi.Catalog

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:filter, fn -> "" end)
     |> assign_new(:selected_chips, fn -> [] end)
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

  def handle_event("select_chip", %{"selector" => selector, "label" => label}, socket) do
    chips = socket.assigns.selected_chips

    if Enum.any?(chips, &(&1.selector == selector)) do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :selected_chips, chips ++ [%{selector: selector, label: label}])}
    end
  end

  def handle_event("remove_chip", %{"selector" => selector}, socket) do
    chips = Enum.reject(socket.assigns.selected_chips, &(&1.selector == selector))
    {:noreply, assign(socket, :selected_chips, chips)}
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

      <%!-- Search across all categories --%>
      <div class="px-4 pb-2">
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

      <%!-- Selected chips strip (hidden when empty) --%>
      <div
        :if={@selected_chips != []}
        class="px-4 pb-2 flex flex-wrap gap-1.5"
      >
        <span
          :for={chip <- @selected_chips}
          class="badge badge-sm badge-primary gap-1"
        >
          {chip.label}
          <button
            type="button"
            phx-click="remove_chip"
            phx-target={@myself}
            phx-value-selector={chip.selector}
            aria-label={"Remove #{chip.label || chip.selector}"}
            class="opacity-70 hover:opacity-100"
          >
            {icon("x", class: "w-2.5 h-2.5")}
          </button>
        </span>
      </div>

      <%!-- Name/address search within selected categories — hidden until a chip is active --%>
      <div :if={@selected_chips != []} class="px-4 pb-2">
        <div class="relative">
          <span class="absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40 pointer-events-none">
            {icon("search", class: "w-3.5 h-3.5")}
          </span>
          <input
            type="search"
            placeholder="Search by name or address…"
            autocomplete="off"
            spellcheck="false"
            class="input input-bordered input-sm w-full pl-8 pr-8"
          />
          <button
            type="button"
            class="absolute right-2 top-1/2 -translate-y-1/2 btn btn-square btn-ghost btn-xs"
            aria-label="Clear name search"
          >
            {icon("x", class: "w-3 h-3")}
          </button>
        </div>
      </div>

      <%!-- Quick picks — always visible pinned tier --%>
      <div class="px-4 pb-2">
        <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 mb-1.5">
          Quick picks
        </div>
        <div class="grid grid-cols-2 gap-1">
          <button
            :for={item <- @pinned}
            type="button"
            phx-click="select_chip"
            phx-target={@myself}
            phx-value-selector={item.selector}
            phx-value-label={item.label}
            class={[
              "flex items-center gap-1.5 px-2 py-1 rounded-md border text-left text-xs truncate transition-colors",
              if(chip_selected?(@selected_chips, item.selector),
                do: "border-primary bg-primary/10 text-primary",
                else: "border-base-300 text-base-content/80 hover:bg-base-200/60 hover:border-base-content/20"
              )
            ]}
            title={item.selector}
          >
            {icon(item.icon,
              class:
                "w-3.5 h-3.5 shrink-0 " <>
                  if(chip_selected?(@selected_chips, item.selector),
                    do: "text-primary",
                    else: "text-base-content/50"
                  )
            )}
            <span class="truncate">{item.label}</span>
          </button>
        </div>
      </div>

      <%!-- Accordion sections / search results --%>
      <div class="px-2 border-t border-base-200 max-h-[40vh] overflow-y-auto">
        <section
          :for={section <- filtered_sections(@sections, @filter)}
          class="border-b border-base-200 last:border-b-0"
        >
          <details class="group">
            <summary class="cursor-pointer select-none w-full px-3 py-3 flex items-center justify-between gap-2 hover:bg-base-200/40 text-left transition-colors list-none [&::-webkit-details-marker]:hidden">
              <span class="flex items-center gap-2 text-xs uppercase tracking-wide text-base-content/70 font-medium">
                <span class="text-base-content/50">
                  {icon(section.icon, class: "w-3.5 h-3.5")}
                </span>
                <span>{section.label}</span>
                <span class="text-[10px] text-base-content/40 tabular-nums font-normal normal-case">
                  {length(section.items)}
                </span>
              </span>
              <span class="text-base-content/40 transition-transform group-open:rotate-180">
                {icon("chevron-down", class: "w-3.5 h-3.5")}
              </span>
            </summary>
            <div class="grid grid-cols-2 gap-1 px-3 pb-3 pt-1">
              <button
                :for={item <- visible_items(section.items, @filter)}
                type="button"
                phx-click="select_chip"
                phx-target={@myself}
                phx-value-selector={item.selector}
                phx-value-label={item.label}
                class={[
                  "flex items-center gap-1.5 px-2 py-1 rounded-md border text-left text-xs truncate transition-colors",
                  if(chip_selected?(@selected_chips, item.selector),
                    do: "border-primary bg-primary/10 text-primary",
                    else: "border-base-300 text-base-content/80 hover:bg-base-200/60 hover:border-base-content/20"
                  )
                ]}
                title={item.selector}
              >
                {icon(item.icon,
                  class:
                    "w-3.5 h-3.5 shrink-0 " <>
                      if(chip_selected?(@selected_chips, item.selector),
                        do: "text-primary",
                        else: "text-base-content/50"
                      )
                )}
                <span class="truncate">{item.label}</span>
              </button>
            </div>
          </details>
        </section>
      </div>

      <%!-- Results list --%>
      <ul class="flex-1 min-h-0 overflow-y-auto px-2 border-t border-base-200">
        <li
          :if={@places == []}
          class="text-xs text-base-content/60 px-2 py-3"
        >
          No places loaded yet.
        </li>
        <li
          :for={place <- @places}
          class="flex items-start gap-2 p-2 rounded-md hover:bg-base-200"
        >
          <span class="text-base-content/40 mt-0.5">
            {icon("map-pin", class: "w-4 h-4")}
          </span>
          <span class="text-sm leading-tight">{place.label}</span>
        </li>
      </ul>
    </div>
    """
  end

  defp chip_selected?(chips, selector), do: Enum.any?(chips, &(&1.selector == selector))

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
