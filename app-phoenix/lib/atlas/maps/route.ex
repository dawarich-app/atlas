defmodule Atlas.Maps.Route do
  alias Atlas.Maps.{Result, Upstream.Valhalla, Upstream.Client}
  require Logger

  @doc """
  Plan a route. Returns:

      {:ok, %Result{features: %{summary: %{}, legs: [...], shape_format: "valhalla_encoded_polyline6"}}}

  Or on upstream failure:

      {:error, %Client.Unavailable{} | %Client.BadResponse{}}
  """
  def plan(opts) do
    case Valhalla.route(opts) do
      {:ok, body} ->
        trip = body["trip"] || %{}

        {:ok,
         %Result{
           features: %{
             summary: trip["summary"] || %{},
             legs: trip["legs"] || [],
             shape_format: "valhalla_encoded_polyline6"
           },
           upstream_status: "ok"
         }}

      {:error, %Client.Unavailable{} = e} ->
        Logger.warning("valhalla unavailable: #{Exception.message(e)}")
        {:error, e}

      {:error, %Client.BadResponse{} = e} ->
        Logger.warning("valhalla bad response: #{Exception.message(e)}")
        {:error, e}
    end
  end
end
