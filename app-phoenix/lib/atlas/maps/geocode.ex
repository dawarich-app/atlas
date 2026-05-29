defmodule Atlas.Maps.Geocode do
  alias Atlas.Maps.{Result, Upstream.Photon, Upstream.Client}
  require Logger

  def lookup(opts) do
    case Photon.search(query: opts[:query], limit: 1, lang: opts[:lang]) do
      {:ok, %{"features" => [first | _]}} -> %Result{features: normalize(first), upstream_status: "ok"}
      {:ok, _} -> %Result{features: nil, upstream_status: "ok"}
      {:error, %Client.Unavailable{} = e} -> Logger.warning("photon unavailable: #{Exception.message(e)}"); %Result{features: nil, upstream_status: "unavailable"}
      {:error, %Client.BadResponse{} = e} -> Logger.warning("photon bad response: #{Exception.message(e)}"); %Result{features: nil, upstream_status: "error"}
    end
  end

  defp normalize(%{"properties" => props, "geometry" => geom}) do
    coords = Map.get(geom, "coordinates", [])
    [lon, lat | _] = coords ++ [nil, nil]
    %{name: props["name"], coords: %{lat: lat, lon: lon}, label: props["name"]}
  end
end
