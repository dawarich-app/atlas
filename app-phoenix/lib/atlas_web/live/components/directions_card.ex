defmodule AtlasWeb.DirectionsCard do
  use AtlasWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <header class="px-4 pt-4 pb-3 border-b border-base-200 flex items-end justify-between gap-3">
        <div>
          <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-primary/80">
            Routing
          </div>
          <h2 class="text-base font-semibold leading-tight mt-0.5 font-display">Directions</h2>
        </div>
        <div class="join">
          <button
            type="button"
            class={"btn btn-sm join-item " <> mode_class(@mode, "auto")}
            phx-click="set_mode"
            phx-value-mode="auto"
            aria-label="Drive"
            title="Drive"
          >
            {icon("car", class: "w-4 h-4")}
          </button>
          <button
            type="button"
            class={"btn btn-sm join-item " <> mode_class(@mode, "bicycle")}
            phx-click="set_mode"
            phx-value-mode="bicycle"
            aria-label="Bike"
            title="Bike"
          >
            {icon("bike", class: "w-4 h-4")}
          </button>
          <button
            type="button"
            class={"btn btn-sm join-item " <> mode_class(@mode, "pedestrian")}
            phx-click="set_mode"
            phx-value-mode="pedestrian"
            aria-label="Walk"
            title="Walk"
          >
            {icon("footprints", class: "w-4 h-4")}
          </button>
          <button
            type="button"
            class={"btn btn-sm join-item " <> mode_class(@mode, "transit")}
            phx-click="set_mode"
            phx-value-mode="transit"
            aria-label="Transit"
            title="Transit"
          >
            {icon("train-front", class: "w-4 h-4")}
          </button>
        </div>
      </header>

      <div class="flex flex-col gap-3 p-4 overflow-y-auto flex-1 min-h-0">
        <form phx-submit="route" class="grid grid-cols-[1fr_auto] gap-2 items-stretch">
          <input type="hidden" name="mode" value={@mode} />
          <div class="flex flex-col gap-2">
            <div class="relative">
              <span class="absolute left-3 top-1/2 -translate-y-1/2 w-2.5 h-2.5 rounded-full bg-info ring-2 ring-base-100">
              </span>
              <input
                type="text"
                name="from"
                placeholder="From (lat,lon)"
                autocomplete="off"
                spellcheck="false"
                class="input input-bordered input-sm w-full pl-8 pr-9"
              />
            </div>
            <div class="relative">
              <span class="absolute left-3 top-1/2 -translate-y-1/2 w-2.5 h-2.5 rounded-sm bg-primary ring-2 ring-base-100">
              </span>
              <input
                type="text"
                name="to"
                placeholder="To (lat,lon)"
                autocomplete="off"
                spellcheck="false"
                class="input input-bordered input-sm w-full pl-8 pr-9"
              />
            </div>
          </div>
          <button
            type="submit"
            class="btn btn-square btn-sm btn-ghost self-center"
            aria-label="Route"
            title="Route"
          >
            {icon("arrow-up-down", class: "w-4 h-4")}
          </button>
        </form>

        <div :if={@directions} class="border-t pt-3 text-xs">
          <div class="flex items-baseline justify-between">
            <div class="flex items-baseline gap-2">
              <span class="text-base font-semibold">Route ready.</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp mode_class(current, mode) when current == mode, do: "btn-primary"
  defp mode_class(_current, _mode), do: "btn-ghost"
end
