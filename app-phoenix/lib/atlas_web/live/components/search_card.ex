defmodule AtlasWeb.SearchCard do
  use AtlasWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <header class="px-4 pt-4 pb-3 border-b border-base-200">
        <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-primary/80">
          Geocoding
        </div>
        <h2 class="text-base font-semibold leading-tight mt-0.5 font-display">Search</h2>
      </header>

      <div class="flex flex-col gap-2 p-4 overflow-y-auto flex-1 min-h-0">
        <form phx-submit="search" class="relative">
          <span class="absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40 pointer-events-none">
            {icon("search", class: "w-4 h-4")}
          </span>
          <input
            type="search"
            name="q"
            value={@query}
            placeholder="Places, addresses…"
            autocomplete="off"
            spellcheck="false"
            class="input input-bordered w-full pl-9 pr-10"
          />
        </form>

        <ul
          :if={@results != []}
          class="bg-base-100 rounded-box w-full max-h-[60vh] overflow-y-auto overflow-x-hidden flex flex-col gap-0.5 list-none p-1 m-0 border border-base-200"
        >
          <li :for={result <- @results} class="list-none">
            <button
              type="button"
              phx-click="select_result"
              phx-value-id={result.id}
              class="w-full text-left flex items-start gap-2 px-2.5 py-2 rounded-md hover:bg-base-200 transition-colors"
            >
              <span class="text-base-content/40 mt-0.5 flex-shrink-0">
                {icon("map-pin", class: "w-4 h-4")}
              </span>
              <span class="flex-1 min-w-0">
                <span class="block text-sm leading-tight truncate">{result.label}</span>
              </span>
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end
end
