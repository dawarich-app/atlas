defmodule Atlas.Maps.Poi do
  @moduledoc """
  Points of interest, by category.

  Two lookups over the category catalog in `Atlas.Maps.Poi.Catalog`:
  `nearby/1` pulls everything in a bbox from Overpass, and
  `search_within_categories/1` does free-text name/address matching via Photon
  scoped to the same categories.
  """

  require Logger
  alias Atlas.Maps.{Poi.Catalog, Result, Upstream.Client, Upstream.Overpass, Upstream.Photon}

  def catalog, do: Catalog.sections()

  def nearby(opts) do
    bbox = opts[:bbox]
    types = opts[:types] || []
    selectors = Catalog.selectors_for(types)

    with :ok <- validate_scope(bbox, types, selectors) do
      [bbox: bbox, filters: selectors, limit: opts[:limit] || 300]
      |> Overpass.bbox()
      |> handle_overpass(types)
    end
  end

  defp handle_overpass({:ok, %{"elements" => elements}}, types) do
    features = Enum.map(elements, &poi_feature(&1, types))
    {:ok, %Result{features: features, upstream_status: "ok"}}
  end

  defp handle_overpass({:error, %Client.Unavailable{} = e}, _types) do
    Logger.warning("overpass unavailable: #{Exception.message(e)}")
    {:error, e}
  end

  defp handle_overpass({:error, %Client.BadResponse{} = e}, _types) do
    Logger.warning("overpass bad response: #{Exception.message(e)}")
    {:error, e}
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

    with :ok <- validate_scope(bbox, types, selectors),
         :ok <- validate_query(query) do
      osm_tags = Enum.map(selectors, &String.replace(&1, "=", ":"))
      # Internal bbox is [s, w, n, e]. Photon expects w,s,e,n.
      [s, w, n, e] = bbox

      [query: query, limit: opts[:limit] || 50, bbox: [w, s, e, n], osm_tags: osm_tags]
      |> Photon.search()
      |> handle_photon(types)
    end
  end

  defp handle_photon({:ok, %{"features" => features}}, types) do
    normalized = Enum.map(features, &normalize_photon_feature(&1, types))
    {:ok, %Result{features: normalized, upstream_status: "ok"}}
  end

  defp handle_photon({:ok, _other}, _types),
    do: {:ok, %Result{features: [], upstream_status: "ok"}}

  defp handle_photon({:error, %Client.Unavailable{} = e}, _types), do: {:error, e}
  defp handle_photon({:error, %Client.BadResponse{} = e}, _types), do: {:error, e}

  defp validate_scope(bbox, types, selectors) do
    cond do
      is_nil(bbox) or length(bbox) != 4 ->
        {:error, :invalid, "bbox required as 's,w,n,e'", %{}}

      selectors == [] ->
        {:error, :invalid, "no known types in #{inspect(types)}", %{types: types}}

      true ->
        :ok
    end
  end

  defp validate_query(query) when is_nil(query) or query == "",
    do: {:error, :invalid, "q required for search_within_categories", %{param: "q"}}

  defp validate_query(_query), do: :ok

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

    base =
      if p["housenumber"], do: Map.put(base, "addr:housenumber", p["housenumber"]), else: base

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
    Enum.find(types, &type_matches?(&1, tags)) || List.first(types) || "other"
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
    Enum.find(types, &type_matches?(&1, tags)) || "other"
  end

  defp type_matches?(type_id, tags) do
    case Catalog.find_item(type_id) do
      nil ->
        false

      %{selector: selector} ->
        [k, v] = String.split(selector, "=", parts: 2)
        tags[k] == v
    end
  end
end
