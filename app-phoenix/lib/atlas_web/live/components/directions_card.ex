defmodule AtlasWeb.DirectionsCard do
  use AtlasWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="card bg-base-200 mb-4">
      <div class="card-body p-4">
        <div class="flex items-start justify-between gap-3">
          <div>
            <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-primary/80">
              Routing
            </div>
            <h2 class="text-base font-semibold leading-tight">Directions</h2>
          </div>
          <div class="join">
            <button
              type="button"
              class={"btn btn-xs join-item " <> mode_class(@mode, "auto")}
              phx-click="set_mode"
              phx-value-mode="auto"
              title="Drive"
            >
              Drive
            </button>
            <button
              type="button"
              class={"btn btn-xs join-item " <> mode_class(@mode, "bicycle")}
              phx-click="set_mode"
              phx-value-mode="bicycle"
              title="Bike"
            >
              Bike
            </button>
            <button
              type="button"
              class={"btn btn-xs join-item " <> mode_class(@mode, "pedestrian")}
              phx-click="set_mode"
              phx-value-mode="pedestrian"
              title="Walk"
            >
              Walk
            </button>
          </div>
        </div>

        <form phx-submit="route" class="mt-3 flex flex-col gap-2">
          <input type="hidden" name="mode" value={@mode} />
          <input
            type="text"
            name="from"
            placeholder="From (lat,lon)"
            class="input input-bordered input-sm w-full"
          />
          <input
            type="text"
            name="to"
            placeholder="To (lat,lon)"
            class="input input-bordered input-sm w-full"
          />
          <button type="submit" class="btn btn-primary btn-sm">Route</button>
        </form>

        <%= if @directions do %>
          <div class="mt-3 border-t border-base-300 pt-2 text-xs">
            <p>Route ready.</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp mode_class(current, mode) when current == mode, do: "btn-primary"
  defp mode_class(_current, _mode), do: "btn-ghost"
end
