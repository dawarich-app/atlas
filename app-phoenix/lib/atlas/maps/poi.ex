defmodule Atlas.Maps.Poi do
  require Logger
  alias Atlas.Maps.{Result, Upstream.Overpass, Upstream.Client, Poi.Catalog}

  def catalog, do: Catalog.sections()

  def nearby(opts) do
    bbox = opts[:bbox]
    types = opts[:types] || []
    selectors = Catalog.selectors_for(types)

    cond do
      is_nil(bbox) or length(bbox) != 4 ->
        {:error, :invalid, "bbox required as 'w,s,e,n'", %{}}

      selectors == [] ->
        {:error, :invalid, "no known types in #{inspect(types)}", %{types: types}}

      true ->
        case Overpass.bbox(bbox: bbox, filters: selectors, limit: opts[:limit] || 300) do
          {:ok, %{"elements" => elements}} ->
            features = Enum.map(elements, &poi_feature(&1, types))
            {:ok, %Result{features: features, upstream_status: "ok"}}

          {:error, %Client.Unavailable{} = e} ->
            Logger.warning("overpass unavailable: #{Exception.message(e)}")
            {:error, e}

          {:error, %Client.BadResponse{} = e} ->
            Logger.warning("overpass bad response: #{Exception.message(e)}")
            {:error, e}
        end
    end
  end

  defp poi_feature(el, types) do
    center = el["center"] || %{"lat" => el["lat"], "lon" => el["lon"]}
    tags = el["tags"] || %{}

    %{
      id: "#{el["type"]}/#{el["id"]}",
      coords: %{lon: center["lon"], lat: center["lat"]},
      name: tags["name"],
      category: derive_category(tags, types),
      tags: tags
    }
  end

  defp derive_category(tags, types) do
    Enum.find(types, fn type_id ->
      case Catalog.find_item(type_id) do
        nil ->
          false

        %{selector: selector} ->
          [k, v] = String.split(selector, "=", parts: 2)
          tags[k] == v
      end
    end)
  end
end
