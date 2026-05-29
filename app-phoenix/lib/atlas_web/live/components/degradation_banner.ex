defmodule AtlasWeb.DegradationBanner do
  use AtlasWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="alert alert-error mb-4 text-sm"
      role="alert"
    >
      <span>Upstream {@status}. Some features may be unavailable.</span>
      <.link navigate={~p"/admin/services"} class="link link-hover font-medium">
        open settings
      </.link>
    </div>
    """
  end
end
