defmodule AtlasWeb.DegradationBanner do
  use AtlasWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed top-0 inset-x-0 z-30 bg-error text-error-content text-sm py-2 px-4 shadow-md flex items-center justify-center gap-3"
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
