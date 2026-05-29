defmodule Atlas.Maps.Poi do
  require Logger
  alias Atlas.Maps.{Result, Upstream.Overpass, Upstream.Photon, Upstream.Client, Poi.Catalog}

  def catalog, do: Catalog.sections()

  def nearby(opts) do
    bbox = opts[:bbox]
    types = opts[:types] || []
    selectors = Catalog.selectors_for(types)

    cond do
      is_nil(bbox) or length(bbox) != 4 ->
        {:error, :invalid, "bbox required as 's,w,n,e'", %{}}

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

  @doc """
  Free-text name/address search via Photon, scoped by bbox + osm_tag filter
  mapped from the user-selected categories.

  Returns `{:ok, %Result{}}` or `{:error, Client.*}`.
  """
  def search_within_categories(opts) do
    bbox = opts[:bbox]
    types = opts[:types] || []
    selectors = Catalog.selectors_for(types)
    query = opts[:query]

    cond do
      is_nil(bbox) or length(bbox) != 4 ->
        {:error, :invalid, "bbox required as 's,w,n,e'", %{}}

      selectors == [] ->
        {:error, :invalid, "no known types in #{inspect(types)}", %{types: types}}

      is_nil(query) or query == "" ->
        {:error, :invalid, "q required for search_within_categories", %{param: "q"}}

      true ->
        osm_tags = Enum.map(selectors, &String.replace(&1, "=", ":"))
        # Internal bbox is [s, w, n, e]. Photon expects w,s,e,n.
        [s, w, n, e] = bbox
        photon_bbox = [w, s, e, n]
        limit = opts[:limit] || 50

        case Photon.search(query: query, limit: limit, bbox: photon_bbox, osm_tags: osm_tags) do
          {:ok, %{"features" => features}} ->
            normalized = Enum.map(features, &normalize_photon_feature(&1, types))
            {:ok, %Result{features: normalized, upstream_status: "ok"}}

          {:ok, _other} ->
            {:ok, %Result{features: [], upstream_status: "ok"}}

          {:error, %Client.Unavailable{} = e} -> {:error, e}
          {:error, %Client.BadResponse{} = e} -> {:error, e}
        end
    end
  end

  defp normalize_photon_feature(feat, types) do
    props = feat["properties"] || %{}
    coords = get_in(feat, ["geometry", "coordinates"]) || []
    [lon, lat | _] = coords ++ [nil, nil]
    tags = osm_tags_from_properties(props)

    %{
      id: "#{props["osm_type"]}/#{props["osm_id"]}",
      coords: %{lon: lon, lat: lat},
      name: props["name"],
      category: derive_category_from_tags(tags, types),
      tags: tags
    }
  end

  defp osm_tags_from_properties(p) do
    base = %{}
    base = if p["name"], do: Map.put(base, "name", p["name"]), else: base
    base = if p["street"], do: Map.put(base, "addr:street", p["street"]), else: base
    base = if p["housenumber"], do: Map.put(base, "addr:housenumber", p["housenumber"]), else: base
    base = if p["postcode"], do: Map.put(base, "addr:postcode", p["postcode"]), else: base
    base = if p["city"], do: Map.put(base, "addr:city", p["city"]), else: base
    base = if p["country"], do: Map.put(base, "addr:country", p["country"]), else: base

    if p["osm_key"] && p["osm_value"] do
      Map.put(base, p["osm_key"], p["osm_value"])
    else
      base
    end
  end

  defp derive_category_from_tags(tags, types) do
    Enum.find_value(types, fn type_id ->
      case Catalog.find_item(type_id) do
        nil ->
          nil

        %{selector: selector} ->
          [k, v] = String.split(selector, "=", parts: 2)
          if tags[k] == v, do: type_id, else: nil
      end
    end) || List.first(types) || "other"
  end

  defp poi_feature(el, types) do
    center = el["center"] || %{"lat" => el["lat"], "lon" => el["lon"]}
    tags = el["tags"] || %{}

    %{
      id: "#{el["type"]}/#{el["id"]}",
      coords: %{lon: center["lon"], lat: center["lat"]},
      name: tags["name"] || tags["brand"],
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
    end) || "other"
  end
end
