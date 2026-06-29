defmodule AtlasWeb.DirectionsCard do
  use Phoenix.Component

  import AtlasWeb.IconHelpers
  import AtlasWeb.Settings.Atoms

  attr :id, :string, required: true
  attr :directions, :any, required: true
  attr :mode, :string, required: true
  attr :route_from, :string, default: ""
  attr :route_to, :string, default: ""
  attr :route_options, :map, default: %{}

  def directions_card(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col h-full">
      <header class="px-4 pt-4">
        <.eyebrow>Routing</.eyebrow>
        <div class="mt-1 flex items-end justify-between gap-3">
          <h2 class="font-display text-3xl font-extrabold leading-none tracking-tight">
            Directions
          </h2>
          <div class="flex gap-1 rounded-xl bg-base-300/40 p-1">
            <.mode_button mode={@mode} value="auto" icon_name="car" label="Drive" />
            <.mode_button mode={@mode} value="bicycle" icon_name="bike" label="Bike" />
            <.mode_button mode={@mode} value="pedestrian" icon_name="footprints" label="Walk" />
            <.mode_button mode={@mode} value="transit" icon_name="train-front" label="Transit" />
          </div>
        </div>
      </header>

      <div class="flex flex-col gap-4 px-4 py-4 overflow-y-auto flex-1 min-h-0">
        <form phx-submit="route" class="grid grid-cols-[1fr_auto] items-stretch gap-2">
          <input type="hidden" name="mode" value={@mode} />
          <div class="flex flex-col gap-2">
            <div class="relative">
              <span class="absolute left-3.5 top-1/2 h-2.5 w-2.5 -translate-y-1/2 rounded-full bg-info ring-2 ring-base-100">
              </span>
              <input
                type="text"
                name="from"
                value={@route_from || ""}
                placeholder="From (lat,lon)"
                autocomplete="off"
                spellcheck="false"
                class="w-full rounded-2xl border-2 border-base-content/10 bg-base-300/40 py-2.5 pl-9 pr-11 text-[14px] text-base-content outline-none transition focus:border-base-content"
              />
              <button
                type="button"
                class="absolute right-2 top-1/2 grid h-[30px] w-[30px] -translate-y-1/2 place-items-center rounded-lg text-base-content/55 transition hover:text-primary"
                title="Pick from on map"
                aria-label="Pick from on map"
                phx-click="pick_point"
                phx-value-field="from"
              >
                {icon("map-pin", class: "w-4 h-4")}
              </button>
            </div>

            <div class="relative">
              <span class="absolute left-3.5 top-1/2 h-2.5 w-2.5 -translate-y-1/2 rounded-sm bg-primary ring-2 ring-base-100">
              </span>
              <input
                type="text"
                name="to"
                value={@route_to || ""}
                placeholder="To (lat,lon)"
                autocomplete="off"
                spellcheck="false"
                class="w-full rounded-2xl border-2 border-base-content/10 bg-base-300/40 py-2.5 pl-9 pr-11 text-[14px] text-base-content outline-none transition focus:border-base-content"
              />
              <button
                type="button"
                class="absolute right-2 top-1/2 grid h-[30px] w-[30px] -translate-y-1/2 place-items-center rounded-lg text-base-content/55 transition hover:text-primary"
                title="Pick to on map"
                aria-label="Pick to on map"
                phx-click="pick_point"
                phx-value-field="to"
              >
                {icon("map-pin", class: "w-4 h-4")}
              </button>
            </div>
          </div>

          <button
            type="button"
            class="grid h-[34px] w-[34px] place-items-center self-center rounded-xl text-base-content/55 transition hover:bg-base-200/60 hover:text-primary"
            aria-label="Swap origin and destination"
            title="Swap"
            phx-click="swap_route"
          >
            {icon("arrow-up-down", class: "w-4 h-4")}
          </button>
        </form>

        <details>
          <summary class="flex cursor-pointer select-none items-center gap-2 font-mono text-[11px] uppercase tracking-[0.2em] text-base-content/55 [&::-webkit-details-marker]:hidden">
            {icon("sliders-horizontal", class: "w-3.5 h-3.5")}
            <span>Options</span>
          </summary>
          <div class="mt-3 flex flex-col gap-2.5 pl-1">
            <.route_option options={@route_options} option="avoid_tolls" label="Avoid tolls" />
            <.route_option options={@route_options} option="avoid_highways" label="Avoid highways" />
            <.route_option options={@route_options} option="avoid_ferries" label="Avoid ferries" />
          </div>
        </details>

        <div :if={@directions} class="rounded-2xl bg-primary/[0.05] px-3.5 py-3">
          <span class="text-[15px] font-semibold">Route ready.</span>
        </div>
      </div>
    </div>
    """
  end

  attr :mode, :string, required: true
  attr :value, :string, required: true
  attr :icon_name, :string, required: true
  attr :label, :string, required: true

  defp mode_button(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "grid h-[30px] w-[34px] place-items-center rounded-lg transition",
        @mode == @value && "bg-primary text-primary-content shadow-sm",
        @mode != @value && "text-base-content/55 hover:text-base-content"
      ]}
      phx-click="set_mode"
      phx-value-mode={@value}
      aria-label={@label}
      title={@label}
    >
      {icon(@icon_name, class: "w-4 h-4")}
    </button>
    """
  end

  attr :options, :map, default: %{}
  attr :option, :string, required: true
  attr :label, :string, required: true

  defp route_option(assigns) do
    ~H"""
    <label class="flex cursor-pointer items-center gap-2.5">
      <input
        type="checkbox"
        class="toggle toggle-xs toggle-primary"
        checked={Map.get(@options || %{}, @option, false)}
        phx-click="toggle_route_option"
        phx-value-option={@option}
      />
      <span class="text-[13.5px] font-medium">{@label}</span>
    </label>
    """
  end
end
