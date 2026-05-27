defmodule Atlas.Control.RegionCatalogTest do
  use ExUnit.Case, async: true

  alias Atlas.Control.RegionCatalog

  setup do
    tmp = Path.join(System.tmp_dir!(), "atlas_region_catalog_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, dir: tmp}
  end

  test "all/1 returns an empty list when the directory is missing" do
    assert RegionCatalog.all("/nonexistent/path/#{System.unique_integer()}") == []
  end

  test "all/1 parses *.env files and exposes name/label/pbf_urls", %{dir: dir} do
    File.write!(Path.join(dir, "berlin.env"), """
    # comment line
    REGION_NAME=berlin
    REGION_LABEL="Berlin (city)"
    COUNTRY_CODE=de
    PBF_URL=https://example.com/berlin.osm.pbf
    DEFAULT_LAT=52.52
    DEFAULT_LON=13.40
    DEFAULT_ZOOM=11
    """)

    [berlin] = RegionCatalog.all(dir)
    assert berlin.name == "berlin"
    assert berlin.label == "Berlin (city)"
    assert berlin.country_code == "de"
    assert berlin.pbf_urls == ["https://example.com/berlin.osm.pbf"]
    assert berlin.default_view == %{lat: 52.52, lon: 13.40, zoom: 11}
  end

  test "all/1 falls back to filename when REGION_NAME is missing", %{dir: dir} do
    File.write!(Path.join(dir, "germany.env"), "PBF_URL=https://example.com/de.pbf\n")
    [r] = RegionCatalog.all(dir)
    assert r.name == "germany"
    assert r.label == "germany"
  end

  test "all/1 expands PBF_URLS into a list", %{dir: dir} do
    File.write!(Path.join(dir, "multi.env"), """
    REGION_NAME=multi
    PBF_URLS=https://a.example/a.pbf https://b.example/b.pbf
    """)

    [r] = RegionCatalog.all(dir)
    assert r.pbf_urls == ["https://a.example/a.pbf", "https://b.example/b.pbf"]
  end

  test "find/2 returns matching region or nil", %{dir: dir} do
    File.write!(Path.join(dir, "berlin.env"), "PBF_URL=https://example.com/berlin.pbf\n")
    assert %RegionCatalog{name: "berlin"} = RegionCatalog.find("berlin", dir)
    assert RegionCatalog.find("notfound", dir) == nil
  end

  test "default dir loads the shipped priv/regions presets" do
    presets = RegionCatalog.all()
    names = Enum.map(presets, & &1.name)
    # priv/regions/ ships these 6 presets at minimum
    for expected <- ~w[berlin europe germany berlin-vienna dach planet] do
      assert expected in names, "expected #{expected} in #{inspect(names)}"
    end
  end
end
