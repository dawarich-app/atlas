defmodule AtlasWeb.SearchCard do
  use AtlasWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="card bg-base-200 mb-4">
      <div class="card-body p-4">
        <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-primary/80">
          Geocoding
        </div>
        <h2 class="text-base font-semibold leading-tight">Search</h2>

        <form phx-submit="search" class="mt-2">
          <input
            type="search"
            name="q"
            value={@query}
            placeholder="Places, addresses…"
            autocomplete="off"
            spellcheck="false"
            class="input input-bordered input-sm w-full"
          />
        </form>

        <%= if @results != [] do %>
          <ul class="menu menu-sm mt-2 bg-base-100 rounded-box p-1 border border-base-300 max-h-[40vh] overflow-y-auto">
            <li :for={result <- @results}>
              <button type="button" phx-click="select_result" phx-value-id={result.id}>
                {result.label}
              </button>
            </li>
          </ul>
        <% end %>
      </div>
    </div>
    """
  end
end
