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
      <header class="px-4 pt-4">
        <AtlasWeb.Settings.Atoms.eyebrow>POIs &amp; categories</AtlasWeb.Settings.Atoms.eyebrow>
        <div class="mt-1 flex items-end justify-between gap-3">
          <h2 class="font-display text-3xl font-extrabold leading-none tracking-tight">Places</h2>
          <button
            type="button"
            phx-click="places_clear"
            class="pb-0.5 text-[12.5px] font-semibold text-base-content/55 transition hover:text-primary"
          >
            clear
          </button>
        </div>
      </header>

      <%!-- Search across all categories --%>
      <div class="px-4 pb-3 pt-4">
        <div class="relative">
          <form phx-change="filter_changed" phx-target={@myself}>
            <input
              type="search"
              name="q"
              value={@filter}
              placeholder="Filter categories…"
              autocomplete="off"
              spellcheck="false"
              class="w-full rounded-2xl border-2 border-base-content/10 bg-base-300/40 px-4 py-2.5 pr-11 text-[14px] text-base-content outline-none transition focus:border-base-content"
            />
          </form>
          <button
            :if={@filter != ""}
            type="button"
            phx-click="clear_filter"
            phx-target={@myself}
            class="absolute right-2 top-1/2 grid h-[30px] w-[30px] -translate-y-1/2 place-items-center rounded-lg text-base-content/55"
            aria-label="Clear filter"
          >
            {icon("x", class: "w-3.5 h-3.5")}
          </button>
          <span
            :if={@filter == ""}
            class="pointer-events-none absolute right-3.5 top-1/2 -translate-y-1/2 text-base-content/55"
          >
            {icon("search", class: "w-[18px] h-[18px]")}
          </span>
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
          <input
            type="search"
            placeholder="Search by name or address…"
            autocomplete="off"
            spellcheck="false"
            class="w-full rounded-2xl border-2 border-base-content/10 bg-base-300/40 px-4 py-2.5 pr-11 text-[14px] text-base-content outline-none transition focus:border-base-content"
          />
          <span class="pointer-events-none absolute right-3.5 top-1/2 -translate-y-1/2 text-base-content/55">
            {icon("search", class: "w-[18px] h-[18px]")}
          </span>
        </div>
      </div>

      <%!-- Quick picks — always visible pinned tier --%>
      <div class="px-4 pb-2">
        <div class="mb-[11px] font-mono text-[11px] uppercase tracking-[0.2em] text-base-content/55">
          Quick picks
        </div>
        <div class="grid grid-cols-2 gap-2">
          <button
            :for={item <- @pinned}
            type="button"
            phx-click="select_chip"
            phx-target={@myself}
            phx-value-selector={item.selector}
            phx-value-label={item.label}
            class={[
              "flex items-center gap-2 truncate rounded-xl border px-2.5 py-2 text-left text-[13px] font-medium transition",
              if(chip_selected?(@selected_chips, item.selector),
                do: "border-primary bg-primary/10 text-primary",
                else: "border-base-content/15 text-base-content/80 hover:bg-base-200/60"
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
      <div class="max-h-[40vh] overflow-y-auto px-4">
        <section
          :for={section <- filtered_sections(@sections, @filter)}
          class="border-t border-base-content/[0.07]"
        >
          <details class="group">
            <summary class="flex w-full cursor-pointer select-none items-center gap-3 px-1 py-3 text-left list-none [&::-webkit-details-marker]:hidden">
              <span class="text-base-content/70">
                {icon(section.icon, class: "w-5 h-5")}
              </span>
              <span class="text-[15px] font-bold uppercase tracking-[0.03em] text-base-content">
                {section.label}
              </span>
              <span class="text-sm font-medium text-base-content/55">
                {length(section.items)}
              </span>
              <span class="ml-auto text-base-content/55 transition-transform duration-200 group-open:rotate-180">
                {icon("chevron-down", class: "w-4 h-4")}
              </span>
            </summary>
            <div class="grid grid-cols-2 gap-2 pb-3 pt-1">
              <button
                :for={item <- visible_items(section.items, @filter)}
                type="button"
                phx-click="select_chip"
                phx-target={@myself}
                phx-value-selector={item.selector}
                phx-value-label={item.label}
                class={[
                  "flex items-center gap-2 truncate rounded-xl border px-2.5 py-2 text-left text-[13px] font-medium transition",
                  if(chip_selected?(@selected_chips, item.selector),
                    do: "border-primary bg-primary/10 text-primary",
                    else: "border-base-content/15 text-base-content/80 hover:bg-base-200/60"
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
      <ul class="min-h-0 flex-1 overflow-y-auto border-t border-base-content/[0.07] px-4 py-2">
        <li :if={@places == []} class="px-1 py-2 text-[13px] text-base-content/60">
          No places loaded yet.
        </li>
        <li
          :for={place <- @places}
          class="flex items-start gap-2.5 rounded-xl px-3 py-2.5 transition hover:bg-base-200/60"
        >
          <span class="mt-0.5 text-base-content/40">
            {icon("map-pin", class: "w-4 h-4")}
          </span>
          <span class="text-sm font-medium leading-tight">{place.label}</span>
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
