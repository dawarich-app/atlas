defmodule AtlasWeb.SearchCard do
  use Phoenix.Component

  import AtlasWeb.IconHelpers
  import AtlasWeb.Settings.Atoms

  attr :id, :string, required: true
  attr :query, :string, required: true
  attr :results, :list, required: true

  def search_card(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col h-full">
      <header class="px-4 pt-4">
        <.eyebrow>Geocoding</.eyebrow>
        <h2 class="mt-1 font-display text-3xl font-extrabold leading-none tracking-tight">
          Search
        </h2>
      </header>

      <div class="flex flex-col gap-4 px-4 py-4 overflow-y-auto flex-1 min-h-0">
        <form phx-submit="search" class="relative">
          <input
            type="search"
            name="q"
            value={@query}
            placeholder="Places, addresses…"
            autocomplete="off"
            spellcheck="false"
            class="w-full rounded-2xl border-2 border-base-content/10 bg-base-300/40 px-4 py-3 pr-11 text-[15px] text-base-content outline-none transition focus:border-base-content"
          />
          <span class="pointer-events-none absolute right-3.5 top-1/2 -translate-y-1/2 text-base-content/55">
            {icon("search", class: "w-[18px] h-[18px]")}
          </span>
        </form>

        <div :if={@results != []}>
          <div class="mb-1.5 font-mono text-[11px] uppercase tracking-[0.2em] text-base-content/55">
            Results
          </div>
          <ul class="flex max-h-[60vh] flex-col gap-1 overflow-y-auto overflow-x-hidden list-none">
            <li :for={result <- @results} class="list-none">
              <button
                type="button"
                phx-click="select_result"
                phx-value-id={result.id}
                class="flex w-full items-start gap-2.5 rounded-xl px-3 py-2.5 text-left transition hover:bg-base-200/60"
              >
                <span class="mt-0.5 flex-shrink-0 text-base-content/40">
                  {icon("map-pin", class: "w-4 h-4")}
                </span>
                <span class="min-w-0 flex-1">
                  <span class="block truncate text-sm font-medium leading-tight">
                    {result.label}
                  </span>
                </span>
              </button>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end
end
