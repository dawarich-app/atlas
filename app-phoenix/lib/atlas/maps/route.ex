defmodule Atlas.Maps.Route do
  alias Atlas.Maps.{Result, Upstream.Valhalla, Upstream.Client}
  require Logger

  def plan(opts) do
    case Valhalla.route(opts) do
      {:ok, body} ->
        {:ok, %Result{features: %{trip: body["trip"]}, upstream_status: "ok"}}

      {:error, %Client.Unavailable{} = e} ->
        Logger.warning("valhalla unavailable: #{Exception.message(e)}")
        {:error, e}

      {:error, %Client.BadResponse{} = e} ->
        Logger.warning("valhalla bad response: #{Exception.message(e)}")
        {:error, e}
    end
  end
end
