defmodule AtlasWeb.PlacesCard do
  use AtlasWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="card bg-base-200 mb-4">
      <div class="card-body p-4">
        <div class="flex items-start justify-between gap-3">
          <div>
            <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-primary/80">
              POIs &amp; categories
            </div>
            <h2 class="text-base font-semibold leading-tight">Places</h2>
          </div>
          <button type="button" phx-click="places_clear" class="btn btn-xs btn-ghost">Clear</button>
        </div>

        <form phx-submit="places_search" class="mt-2">
          <input
            type="search"
            name="q"
            placeholder="Filter categories…"
            autocomplete="off"
            class="input input-bordered input-sm w-full"
          />
        </form>

        <%= if @places != [] do %>
          <ul class="menu menu-sm mt-2 bg-base-100 rounded-box p-1 border border-base-300 max-h-[40vh] overflow-y-auto">
            <li :for={place <- @places}>
              <span>{place.label}</span>
            </li>
          </ul>
        <% else %>
          <p class="mt-2 text-xs text-base-content/60">No places loaded yet.</p>
        <% end %>
      </div>
    </div>
    """
  end
end
