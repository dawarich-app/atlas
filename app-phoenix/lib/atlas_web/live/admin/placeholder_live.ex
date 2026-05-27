defmodule AtlasWeb.Admin.PlaceholderLive do
  @moduledoc """
  Placeholder LiveView used during M3 build-out before the real admin
  LiveViews land (Tasks 6-10). Routes that pass admin auth land here so
  the auth pipeline test can fire end-to-end.
  """
  use AtlasWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Admin")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1 class="text-2xl font-bold">Admin (placeholder)</h1>
    <p class="opacity-70">This view will be replaced as the admin LiveViews land.</p>
    """
  end
end
