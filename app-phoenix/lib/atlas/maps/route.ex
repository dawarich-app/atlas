defmodule Atlas.Maps.Route do
  alias Atlas.Maps.{Result, Upstream.Valhalla, Upstream.Client}
  require Logger

  def plan(opts) do
    case Valhalla.route(opts) do
      {:ok, body} -> %Result{features: %{trip: body["trip"]}, upstream_status: "ok"}
      {:error, %Client.Unavailable{} = e} -> Logger.warning("valhalla unavailable: #{Exception.message(e)}"); %Result{features: %{trip: nil}, upstream_status: "unavailable"}
      {:error, %Client.BadResponse{} = e} -> Logger.warning("valhalla bad response: #{Exception.message(e)}"); %Result{features: %{trip: nil}, upstream_status: "error"}
    end
  end
end
