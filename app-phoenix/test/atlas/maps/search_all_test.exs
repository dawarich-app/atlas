defmodule Atlas.Maps.SearchAllTest do
  use ExUnit.Case, async: true

  alias Atlas.Maps.SearchAll

  defp feature(id, lon, lat) do
    %{
      "geometry" => %{"coordinates" => [lon, lat]},
      "properties" => %{"osm_type" => "N", "osm_id" => id, "name" => "McDonald's"}
    }
  end

  defp dataset_fetch(features) do
    fn opts ->
      [w, s, e, n] = opts[:bbox]
      assert opts[:dedupe] == false
      assert opts[:query] == "McDonald's"

      matches =
        features
        |> Enum.filter(fn %{"geometry" => %{"coordinates" => [lon, lat]}} ->
          lon >= w and lon <= e and lat >= s and lat <= n
        end)
        |> Enum.take(opts[:limit])

      {:ok, %{"features" => matches}}
    end
  end

  test "collects every match beyond the upstream cap across the entire dataset" do
    features = Enum.map(1..137, &feature(&1, -170 + &1 * 2, -40 + rem(&1, 70)))
    result = SearchAll.run("McDonald's", fetch: dataset_fetch(features), page_size: 5)
    assert result.complete
    assert length(result.features) == 137

    assert MapSet.new(Enum.map(result.features, & &1.id)) ==
             MapSet.new(Enum.map(1..137, &"N:#{&1}"))

    assert result.requests > 1
  end

  test "overlapping cell edges and repeated OSM IDs count only once" do
    features = [feature(1, 0, 0), feature(1, 0, 0), feature(2, -20, 10), feature(3, 20, 10)]
    result = SearchAll.run("McDonald's", fetch: dataset_fetch(features), page_size: 3)
    assert result.complete
    assert length(result.features) == 3
  end

  test "an exhausted request budget never claims all results have loaded" do
    features = Enum.map(1..5, &feature(&1, &1, &1))

    result =
      SearchAll.run("McDonald's", fetch: dataset_fetch(features), page_size: 2, max_requests: 1)

    refute result.complete
    assert length(result.features) == 2
  end

  test "coincident overflowing results terminate with an honest incomplete count" do
    features = Enum.map(1..5, &feature(&1, 10, 10))

    result =
      SearchAll.run("McDonald's", fetch: dataset_fetch(features), page_size: 2, max_depth: 3)

    refute result.complete
    assert length(result.features) == 2
  end

  test "a failed cell preserves found matches and reports incomplete coverage" do
    fetch = fn opts ->
      if opts[:bbox] == [-180.0, -90.0, 180.0, 90.0],
        do: {:ok, %{"features" => [feature(1, -10, 10), feature(2, 10, 10)]}},
        else: {:error, :unreachable}
    end

    result = SearchAll.run("McDonald's", fetch: fetch, page_size: 2)
    refute result.complete
    assert length(result.features) == 2
  end

  test "progress stays incomplete until every pending cell has been checked" do
    owner = self()
    features = Enum.map(1..10, &feature(&1, &1, &1))

    result =
      SearchAll.run("McDonald's",
        fetch: dataset_fetch(features),
        page_size: 3,
        on_progress: &send(owner, {:progress, &1})
      )

    assert result.complete
    assert_receive {:progress, %{complete: false, features: [_ | _]}}
  end
end
