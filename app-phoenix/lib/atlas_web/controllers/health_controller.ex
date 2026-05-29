defmodule AtlasWeb.HealthController do
  use AtlasWeb, :controller

  def show(conn, _params), do: text(conn, "ok")
end
