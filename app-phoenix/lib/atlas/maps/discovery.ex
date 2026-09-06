defmodule Atlas.Maps.Discovery do
  @moduledoc "Unified name/address search and optional category discovery."
  alias Atlas.Maps.{Poi.Catalog, SearchAll, Upstream.Overpass}

  def category_ids(value) when is_binary(value) do
    value |> String.split(",") |> Enum.uniq() |> Enum.filter(&Catalog.find_item/1) |> Enum.sort()
  end

  def category_ids(_), do: []

  def bbox(value) when is_binary(value) do
    parts = String.split(value, ",")
    parsed = Enum.map(parts, &Float.parse/1)

    case parsed do
      [{w, ""}, {s, ""}, {e, ""}, {n, ""}]
      when w >= -180 and e <= 180 and s >= -90 and n <= 90 and w < e and s < n ->
        [w, s, e, n]

      _ ->
        nil
    end
  end

  def bbox(_), do: nil

  def suggestions(query) do
    needle = normalize(String.trim(query))

    if needle == "" do
      []
    else
      Catalog.sections()
      |> Enum.flat_map(& &1.items)
      |> Enum.filter(&String.contains?(normalize(&1.label), needle))
      |> Enum.take(5)
    end
  end

  defp normalize(text) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfkd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
  end

  def run(query, categories, opts \\ []) do
    selectors = Catalog.selectors_for(categories)

    if String.trim(query) == "" and selectors != [] do
      opts =
        Keyword.merge(opts,
          fetch: &fetch_categories(&1, selectors),
          page_size: 500,
          concurrency: 2,
          request_timeout: 30_000
        )

      SearchAll.run("", opts)
    else
      SearchAll.run(
        query,
        Keyword.put(opts, :osm_tags, Enum.map(selectors, &String.replace(&1, "=", ":")))
      )
    end
  end

  defp fetch_categories(opts, selectors) do
    [w, s, e, n] = opts[:bbox]

    case Overpass.bbox(
           bbox: [s, w, n, e],
           filters: selectors,
           limit: opts[:limit],
           relations: true
         ) do
      {:ok, %{"remark" => _}} ->
        {:error, :incomplete_upstream}

      {:ok, %{"elements" => elements}} ->
        {:ok, %{"features" => Enum.map(elements, &feature(&1, selectors))}}

      other ->
        other
    end
  end

  defp feature(element, selectors) do
    tags = element["tags"] || %{}
    center = element["center"] || element

    selector =
      Enum.find(selectors, fn selector ->
        [key, value] = String.split(selector, "=", parts: 2)
        tags[key] == value
      end) || hd(selectors)

    [key, value] = String.split(selector, "=", parts: 2)

    %{
      "geometry" => %{"coordinates" => [center["lon"], center["lat"]]},
      "properties" => %{
        "osm_type" => %{"node" => "N", "way" => "W", "relation" => "R"}[element["type"]],
        "osm_id" => element["id"],
        "osm_key" => key,
        "osm_value" => value,
        "name" => tags["name"] || tags["brand"] || String.replace(value, "_", " "),
        "street" => tags["addr:street"],
        "housenumber" => tags["addr:housenumber"],
        "city" => tags["addr:city"],
        "postcode" => tags["addr:postcode"],
        "country" => tags["addr:country"]
      }
    }
  end
end
