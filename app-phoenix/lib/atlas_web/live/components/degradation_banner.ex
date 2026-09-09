defmodule AtlasWeb.DegradationBanner do
  @moduledoc """
  Banner shown when one or more upstream services are unavailable.
  """

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
      <button type="button" phx-click="open_services" class="link link-hover font-medium">
        open settings
      </button>
    </div>
    """
  end
end
