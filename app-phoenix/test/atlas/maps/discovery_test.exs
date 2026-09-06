defmodule Atlas.Maps.DiscoveryTest do
  use ExUnit.Case, async: true
  alias Atlas.Maps.{Discovery, SearchAll}

  test "only catalog categories and valid ordered coordinates enter a query" do
    assert Discovery.category_ids("cafe,invalid,cafe,restaurant") == ["cafe", "restaurant"]
    assert Discovery.bbox("13,52,14,53") == [13.0, 52.0, 14.0, 53.0]

    for value <- ["a,b,c,d", "14,52,13,53", "-181,-90,180,90", "13,52,14,91", "1,2,3"] do
      assert Discovery.bbox(value) == nil
    end
  end

  test "category suggestions match accents without silently applying categories" do
    assert Enum.any?(Discovery.suggestions("cafe"), &(&1.id == "cafe"))
    assert Discovery.suggestions("") == []
    assert Discovery.suggestions("McDonald's") == []
  end

  test "subdivision preserves the category restriction and selected area" do
    owner = self()

    fetch = fn opts ->
      send(owner, {:request, opts})
      [w, s, e, n] = opts[:bbox]

      features =
        for {id, lon} <- [{1, 13.2}, {2, 13.8}],
            lon >= w and lon <= e and s <= 52.5 and n >= 52.5 do
          %{
            "geometry" => %{"coordinates" => [lon, 52.5]},
            "properties" => %{"osm_type" => "N", "osm_id" => id, "name" => "Café"}
          }
        end

      {:ok, %{"features" => Enum.take(features, opts[:limit])}}
    end

    result =
      SearchAll.run("Café",
        bbox: [13.0, 52.0, 14.0, 53.0],
        osm_tags: ["amenity:cafe"],
        page_size: 2,
        fetch: fetch
      )

    assert result.complete
    assert length(result.features) == 2
    assert_receive {:request, opts}
    assert opts[:bbox] == [13.0, 52.0, 14.0, 53.0]
    assert_receive {:request, child_opts}
    assert child_opts[:osm_tags] == ["amenity:cafe"]
    assert child_opts[:bbox] != opts[:bbox]
  end
end
