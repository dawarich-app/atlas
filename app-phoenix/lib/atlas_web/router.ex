defmodule AtlasWeb.Router do
  use AtlasWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
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
end
