defmodule AtlasWeb.DirectionsCard do
  @moduledoc """
  The directions panel — mode switcher, endpoints, and the resulting itinerary.
  """

  use Phoenix.Component

  alias AtlasWeb.RouteDetails

  import AtlasWeb.CoreComponents, only: [input: 1]
  import AtlasWeb.IconHelpers
  import AtlasWeb.Settings.Atoms

  attr :id, :string, required: true
  attr :directions, :any, required: true
  attr :mode, :string, required: true
  attr :route_from, :string, default: ""
  attr :route_to, :string, default: ""
  attr :route_endpoints, :map, default: %{}
  attr :route_focus, :string, default: nil
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
        <form phx-submit="route" phx-change="route_changed" phx-click-away="route_dismiss" class="grid grid-cols-[1fr_auto] items-stretch gap-2">
          <input type="hidden" name="mode" value={@mode} />
          <div class="flex min-w-0 flex-col gap-2">
            <.endpoint field="from" label="From" value={@route_from}
              endpoint={Map.get(@route_endpoints, "from", AtlasWeb.RouteEndpoint.new())} focus={@route_focus} />
            <.endpoint field="to" label="To" value={@route_to}
              endpoint={Map.get(@route_endpoints, "to", AtlasWeb.RouteEndpoint.new())} focus={@route_focus} />
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

          <button
            type="submit"
            class="col-span-2 mt-1 flex items-center justify-center gap-2 rounded-2xl bg-primary py-2.5 text-[14px] font-semibold text-primary-content transition hover:brightness-110"
          >
            {icon("route", class: "w-4 h-4")}
            <span>Get directions</span>
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
          <p class="text-[15px] font-semibold">{RouteDetails.label(@directions[:route_mode] || @mode)} · {RouteDetails.duration(@directions)}</p>
          <%= if itinerary = RouteDetails.itinerary(@directions) do %>
            <p :if={not RouteDetails.transit?(itinerary)} role="status" class="mt-2 text-sm text-warning">
              No public transport connection returned. This alternative is walking only.
            </p>
            <p class="mt-1 text-xs text-base-content/65">Dashed grey: walk · Blue: transport</p>
            <ol class="mt-3 space-y-2 text-sm">
              <li :for={leg <- itinerary.legs}>
                <span class="font-semibold">{RouteDetails.label(leg.mode)} {leg.route_name}</span>
                <span class="text-base-content/60"> · {RouteDetails.minutes(leg.duration)}</span>
                <p :if={leg.to[:name]} class="text-xs text-base-content/65">To {leg.to.name}</p>
              </li>
            </ol>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :endpoint, :map, required: true
  attr :focus, :string, default: nil

  defp endpoint(assigns) do
    assigns =
      assign(
        assigns,
        :expanded,
        assigns.focus == assigns.field and assigns.endpoint.results != []
      )

    ~H"""
    <div id={"route-#{@field}-field"}>
      <div class="relative [&_.fieldset]:p-0">
        <span class={["pointer-events-none absolute left-3.5 top-1/2 z-10 h-2.5 w-2.5 -translate-y-1/2 ring-2 ring-base-100", if(@field == "from", do: "rounded-full bg-info", else: "rounded-sm bg-primary")]}></span>
        <.input type="text" id={"route-#{@field}"} name={@field} value={@value}
          placeholder={"#{@label}: address, place or coordinates"} aria-label={@label}
          role="combobox" aria-autocomplete="list" aria-expanded={to_string(@expanded)}
          aria-controls={if @expanded, do: "route-#{@field}-results"}
          aria-activedescendant={if @expanded and @endpoint.active >= 0, do: "route-#{@field}-option-#{@endpoint.active}"}
          autocomplete="off" spellcheck="false" phx-debounce="300" phx-hook="RouteKeys"
          data-field={@field} data-query={@endpoint.query}
          data-has-active={to_string(@expanded and @endpoint.active >= 0)}
          phx-focus="route_focus" phx-value-field={@field}
          class="w-full rounded-2xl border-2 border-base-content/10 bg-base-300/40 py-2.5 pl-9 pr-11 text-[14px] text-base-content outline-none transition focus:border-base-content" />
        <button type="button"
          class="absolute right-2 top-1/2 grid h-[30px] w-[30px] -translate-y-1/2 place-items-center rounded-lg text-base-content/55 transition hover:text-primary"
          title={"Pick #{@field} on map"} aria-label={"Pick #{@field} on map"}
          phx-click="pick_point" phx-value-field={@field}>
          {icon("map-pin", class: "w-4 h-4")}
        </button>
      </div>
      <div :if={@focus == @field}>
        <p :if={@endpoint.status == :loading} role="status" class="px-3 py-2 text-xs text-base-content/60">Searching…</p>
        <p :if={@endpoint.status == :error} role="status" class="px-3 py-2 text-xs text-error">Search unavailable. Enter coordinates or
          <button type="button" class="link link-primary" phx-click="route_retry" phx-value-field={@field}>Retry search</button>.
        </p>
        <p :if={@endpoint.status == :invalid} role="status" class="px-3 py-2 text-xs text-error">Latitude must be between −90 and 90; longitude between −180 and 180.</p>
        <p :if={@endpoint.status == :ready and @endpoint.results == []} role="status" class="px-3 py-2 text-xs text-base-content/60">No places found. Try a fuller address or coordinates.</p>
        <ul :if={@expanded} id={"route-#{@field}-results"} role="listbox" aria-label={"#{@label} suggestions"}
          class="mt-1 max-h-48 overflow-y-auto rounded-xl bg-base-100 p-1 shadow-sm">
          <li :for={{place, index} <- Enum.with_index(@endpoint.results)} role="presentation">
            <button type="button" role="option" id={"route-#{@field}-option-#{index}"}
              aria-selected={to_string(index == @endpoint.active)} tabindex="-1"
              phx-click="route_select" phx-value-field={@field} phx-value-index={index} phx-value-query={@endpoint.query}
              class={["block w-full rounded-lg px-3 py-2 text-left text-sm leading-snug", if(index == @endpoint.active, do: "bg-primary/10", else: "hover:bg-base-200")]}>
              {place.label}
            </button>
          </li>
        </ul>
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
