defmodule Mix.Tasks.Atlas.GenCatalogTest do
  use ExUnit.Case, async: true

  @geofabrik_fixture Path.join(System.tmp_dir!(), "gf_fixture.json")

  setup do
    File.write!(@geofabrik_fixture, Jason.encode!(%{"features" => [
      %{"properties" => %{"id" => "europe", "parent" => nil, "name" => "Europe", "urls" => %{"pbf" => "https://x/eu.pbf"}}}
    ]}))
    on_exit(fn -> File.rm_rf!(@geofabrik_fixture) end)
    :ok
  end

  test "parse_bbbike_index/1 extracts city names from the directory HTML" do
    html = ~s(<a href="Berlin/">Berlin/</a> <a href="Wien/">Wien/</a> <a href="../">../</a>)
    assert Mix.Tasks.Atlas.GenCatalog.parse_bbbike_index(html) == ["Berlin", "Wien"]
  end
end
