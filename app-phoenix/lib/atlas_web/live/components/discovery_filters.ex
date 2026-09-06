defmodule AtlasWeb.DiscoveryFilters do
  @moduledoc "Optional category chips and an explicit geographic scope for unified search."
  use Phoenix.Component
  import AtlasWeb.IconHelpers
  alias Atlas.Maps.{Discovery, Poi.Catalog}

  attr :query, :string, required: true
  attr :categories, :list, required: true
  attr :scope, :string, required: true
  attr :area_changed, :boolean, default: false
  attr :viewport_ready, :boolean, default: false

  def filters(assigns) do
    assigns =
      assign(assigns,
        selected: Enum.map(assigns.categories, &Catalog.find_item/1),
        suggestions: Discovery.suggestions(assigns.query),
        quick: Enum.map(~w(cafe restaurant parking fast_food), &Catalog.find_item/1),
        sections: Catalog.sections()
      )

    ~H"""
    <div class="space-y-3">
      <div class="flex flex-wrap gap-2 items-center text-xs" aria-label="Search area">
        <span class="font-semibold">Search in</span>
        <button type="button" phx-click="search_scope" phx-value-scope="all"
          aria-pressed={to_string(@scope == "all")}
          class={["rounded-full border px-2.5 py-1.5", if(@scope == "all", do: "bg-primary/10 border-primary text-primary", else: "border-base-content/20")]}>
          All installed data
        </button>
        <button type="button" phx-click="search_scope" phx-value-scope="area"
          disabled={not @viewport_ready} aria-pressed={to_string(@scope == "area")}
          class={["rounded-full border px-2.5 py-1.5 disabled:opacity-40", if(@scope == "area", do: "bg-primary/10 border-primary text-primary", else: "border-base-content/20")]}>
          This map area
        </button>
      </div>
      <div :if={@scope == "area" and @area_changed} id="search-area-changed" class="rounded-xl bg-base-200 p-3 text-xs">
        Results refer to the previously searched area.
        <button type="button" phx-click="search_here" class="link link-primary ml-1 font-semibold">Search here</button>
      </div>
      <div :if={@selected != []} class="flex flex-wrap gap-1.5" aria-label="Active categories">
        <button :for={item <- @selected} type="button" phx-click="toggle_category" phx-value-id={item.id}
          aria-label={"Remove #{item.label}"} class="flex items-center gap-2 rounded-full bg-primary text-primary-content px-3 py-1.5 text-xs">
          {item.label}{icon("x", class: "w-3 h-3")}
        </button>
        <span :if={length(@selected) > 1} class="self-center text-xs text-base-content/60">Matches any selected category</span>
      </div>
      <div :if={@suggestions != []} id="category-suggestions" class="rounded-xl border border-base-content/10 p-2">
        <p class="px-1 pb-1 text-[11px] uppercase tracking-wide opacity-60">Categories</p>
        <button :for={item <- @suggestions} type="button" phx-click="choose_category" phx-value-id={item.id}
          class="flex w-full items-center gap-2 rounded-lg px-2 py-2 text-left text-sm hover:bg-primary/10">
          {icon(item.icon, class: "w-4 h-4")}<span>{item.label}</span><span class="ml-auto text-xs opacity-60">Category</span>
        </button>
      </div>
      <div class="flex flex-wrap gap-1.5" aria-label="Optional categories">
        <.category_button :for={item <- @quick} item={item} selected={item.id in @categories} />
        <details class="w-full group" id="more-categories">
          <summary class="cursor-pointer py-2 text-xs font-semibold text-primary">More categories</summary>
          <div class="max-h-64 overflow-y-auto space-y-2 rounded-xl border border-base-content/10 p-2 mt-1">
            <details :for={section <- @sections} id={"category-section-#{section.id}"}>
              <summary class="cursor-pointer py-2 text-xs font-semibold">{section.label}</summary>
              <div class="flex flex-wrap gap-1.5 pb-2">
                <.category_button :for={item <- section.items} item={item} selected={item.id in @categories} />
              </div>
            </details>
          </div>
        </details>
      </div>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :selected, :boolean, required: true

  defp category_button(assigns) do
    ~H"""
    <button type="button" phx-click="toggle_category" phx-value-id={@item.id}
      aria-pressed={to_string(@selected)}
      class={["flex items-center gap-1.5 rounded-full border px-2.5 py-1.5 text-xs transition", if(@selected, do: "border-primary bg-primary/10 text-primary", else: "border-base-content/15 hover:bg-base-100")]}>
      {icon(@item.icon, class: "w-3.5 h-3.5")}{@item.label}
    </button>
    """
  end
end
