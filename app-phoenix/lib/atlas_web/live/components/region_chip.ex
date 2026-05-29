defmodule AtlasWeb.RegionChip do
  use AtlasWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click="toggle"
      phx-value-name={@region.name}
      class={["btn btn-sm", if(@selected, do: "btn-primary", else: "btn-outline")]}
    >
      {@region.label}
    </button>
    """
  end
end
