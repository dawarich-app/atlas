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

  scope "/", AtlasWeb do
    get "/up", HealthController, :show
  end
end
