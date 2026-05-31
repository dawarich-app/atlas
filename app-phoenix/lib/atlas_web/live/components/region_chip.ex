defmodule AtlasWeb.RegionChip do
  use Phoenix.Component

  attr :id, :string, required: true
  attr :region, :map, required: true
  attr :selected, :boolean, default: false

  def region_chip(assigns) do
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
