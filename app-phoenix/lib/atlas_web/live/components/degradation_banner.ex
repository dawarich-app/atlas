defmodule AtlasWeb.DegradationBanner do
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: AtlasWeb.Endpoint,
    router: AtlasWeb.Router,
    statics: AtlasWeb.static_paths()

  attr :id, :string, required: true
  attr :status, :string, required: true

  def degradation_banner(assigns) do
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
