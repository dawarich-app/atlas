defmodule AtlasWeb.Router do
  use AtlasWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: AtlasWeb.ApiSpec
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AtlasWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin_auth do
    plug AtlasWeb.Plugs.AdminAuth
  end

  scope "/api/v1", AtlasWeb.Api.V1 do
    pipe_through :api

    get "/search", SearchController, :index
    get "/reverse", ReverseController, :show
    post "/reverse/batch", ReverseController, :batch
    get "/route", RouteController, :show
    get "/transit", TransitController, :show
    get "/whats-here", WhatsHereController, :index
    get "/pois", PoisController, :index
    get "/pois/categories", PoisController, :categories
    get "/geocode", GeocodeController, :index
  end

  scope "/api" do
    pipe_through :api
    get "/v1/openapi.json", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/", AtlasWeb do
    pipe_through :browser
    # MapLive at "/" lands in Task 5
  end

  scope "/admin", AtlasWeb.Admin, as: :admin do
    pipe_through [:browser, :admin_auth]

    live_session :admin, layout: {AtlasWeb.Layouts, :admin} do
      # Placeholder routes — replaced by real LiveViews in Tasks 6-10.
      live "/services", PlaceholderLive, :index
      live "/services/:name/logs", PlaceholderLive, :show
      live "/regions", PlaceholderLive, :index
      live "/tiles", PlaceholderLive, :index
      live "/apply", PlaceholderLive, :index
    end
  end

  scope "/", AtlasWeb do
    get "/up", HealthController, :show
  end
end
