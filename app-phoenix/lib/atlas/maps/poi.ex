defmodule Atlas.Maps.Poi do
  require Logger
  alias Atlas.Maps.{Result, Upstream.Overpass, Upstream.Client, Poi.Catalog}

  def catalog, do: Catalog.all()

  def nearby(opts) do
    case Catalog.find(opts[:category]) do
      nil ->
        %Result{features: [], upstream_status: "error"}

      cat ->
        case Overpass.around(lat: opts[:lat], lon: opts[:lon], radius: opts[:radius] || 500, osm_tags: cat.osm_tags) do
          {:ok, %{"elements" => elements}} -> %Result{features: Enum.map(elements, &poi_feature/1), upstream_status: "ok"}
          {:error, %Client.Unavailable{} = e} -> Logger.warning("overpass unavailable: #{Exception.message(e)}"); %Result{features: [], upstream_status: "unavailable"}
          {:error, %Client.BadResponse{} = e} -> Logger.warning("overpass bad response: #{Exception.message(e)}"); %Result{features: [], upstream_status: "error"}
        end
    end
  end

  defp poi_feature(el) do
    center = el["center"] || %{"lat" => el["lat"], "lon" => el["lon"]}
    %{
      id: "#{el["type"]}/#{el["id"]}",
      coords: %{lon: center["lon"], lat: center["lat"]},
      tags: el["tags"] || %{}
    }
  end
end
