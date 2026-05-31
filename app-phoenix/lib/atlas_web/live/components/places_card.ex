defmodule AtlasWeb.PlacesCard do
  use AtlasWeb, :live_component

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

      <div class="px-4 pt-3 pb-2">
        <form phx-submit="places_search" class="relative">
          <span class="absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40 pointer-events-none">
            {icon("search", class: "w-4 h-4")}
          </span>
          <input
            type="search"
            name="q"
            placeholder="Filter categories…"
            autocomplete="off"
            spellcheck="false"
            class="input input-bordered input-sm w-full pl-9 pr-9"
          />
        </form>
      </div>

      <div class="px-4 pb-2">
        <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 mb-1.5">
          Quick picks
        </div>
        <div class="grid grid-cols-2 gap-1">
          <button type="button" class="btn btn-sm btn-ghost justify-start gap-2">
            {icon("map-pin", class: "w-3.5 h-3.5")} Food
          </button>
          <button type="button" class="btn btn-sm btn-ghost justify-start gap-2">
            {icon("map-pin", class: "w-3.5 h-3.5")} Shops
          </button>
          <button type="button" class="btn btn-sm btn-ghost justify-start gap-2">
            {icon("map-pin", class: "w-3.5 h-3.5")} Cafés
          </button>
          <button type="button" class="btn btn-sm btn-ghost justify-start gap-2">
            {icon("map-pin", class: "w-3.5 h-3.5")} Transit
          </button>
        </div>
      </div>

      <div class="flex-1 min-h-0 overflow-y-auto px-4 py-2 border-t border-base-200">
        <p :if={@places == []} class="text-xs text-base-content/60">
          Pick a category or search to load places near here.
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
end
