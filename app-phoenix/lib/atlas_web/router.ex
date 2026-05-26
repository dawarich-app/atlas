defmodule AtlasWeb.Router do
  use AtlasWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", AtlasWeb do
    pipe_through :api
  end
end
