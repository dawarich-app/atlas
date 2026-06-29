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

  test "struct carries kind, parent, and pbf_bytes with nil defaults" do
    r = %RegionCatalog{name: "x", label: "X", pbf_urls: []}
    assert r.kind == nil
    assert r.parent == nil
    assert r.pbf_bytes == nil
  end

  test "load_catalog/1 parses catalog.json into structs", %{dir: dir} do
    File.write!(Path.join(dir, "catalog.json"), Jason.encode!([
      %{
        "name" => "gf:germany",
        "label" => "Germany",
        "kind" => "country",
        "source" => "geofabrik",
        "parent" => "gf:europe",
        "country_code" => "de",
        "iso" => ["DE"],
        "pbf_url" => "https://download.geofabrik.de/europe/germany-latest.osm.pbf",
        "pbf_bytes" => 4_000_000_000
      }
    ]))

    [g] = RegionCatalog.load_catalog(dir)
    assert g.name == "gf:germany"
    assert g.kind == "country"
    assert g.parent == "gf:europe"
    assert g.pbf_urls == ["https://download.geofabrik.de/europe/germany-latest.osm.pbf"]
    assert g.pbf_bytes == 4_000_000_000
  end

  test "load_catalog/1 returns [] for a missing or malformed file", %{dir: dir} do
    assert RegionCatalog.load_catalog(dir) == []
    File.write!(Path.join(dir, "catalog.json"), "{not json")
    assert RegionCatalog.load_catalog(dir) == []
  end

  test "all/1 merges curated .env presets with catalog.json; curated wins on name clash", %{dir: dir} do
    File.write!(Path.join(dir, "germany.env"), """
    REGION_NAME=germany
    REGION_LABEL="Germany (curated)"
    PBF_URL=https://curated.example/de.pbf
    """)

    File.write!(Path.join(dir, "catalog.json"), Jason.encode!([
      %{"name" => "germany", "label" => "Germany (baked)", "kind" => "country",
        "pbf_url" => "https://baked.example/de.pbf"},
      %{"name" => "gf:france", "label" => "France", "kind" => "country",
        "pbf_url" => "https://baked.example/fr.pbf"}
    ]))

    all = RegionCatalog.all(dir)
    names = Enum.map(all, & &1.name)

    assert "germany" in names
    assert "gf:france" in names
    germany = Enum.find(all, &(&1.name == "germany"))
    assert germany.label == "Germany (curated)"
  end

  test "size_label/1 prefers real bytes, falls back to tier hint" do
    with_bytes = %RegionCatalog{name: "gf:de", label: "DE", pbf_urls: [], pbf_bytes: 4_100_000_000}
    assert RegionCatalog.size_label(with_bytes) == "4.1 GB"

    small = %RegionCatalog{name: "bbbike:berlin", label: "Berlin", pbf_urls: [], pbf_bytes: 31_457_280}
    assert RegionCatalog.size_label(small) == "31.5 MB"

    no_bytes = %RegionCatalog{name: "planet", label: "Planet", pbf_urls: [], pbf_bytes: nil}
    assert RegionCatalog.size_label(no_bytes) == "~1.1 TB"
  end

  describe "tree + search helpers" do
    setup %{dir: dir} do
      File.write!(Path.join(dir, "catalog.json"), Jason.encode!([
        %{"name" => "gf:europe", "label" => "Europe", "kind" => "continent", "parent" => nil, "pbf_url" => "x"},
        %{"name" => "gf:germany", "label" => "Germany", "kind" => "country", "parent" => "gf:europe", "country_code" => "de", "iso" => ["DE"], "pbf_url" => "x"},
        %{"name" => "gf:germany/bayern", "label" => "Bayern", "kind" => "subregion", "parent" => "gf:germany", "iso" => ["DE-BY"], "pbf_url" => "x"},
        %{"name" => "bbbike:berlin", "label" => "Berlin", "kind" => "city", "parent" => "gf:germany", "pbf_url" => "x"}
      ]))
      :ok
    end

    test "roots/1 returns parentless entries", %{dir: dir} do
      assert Enum.map(RegionCatalog.roots(dir), & &1.name) == ["gf:europe"]
    end

    test "children/2 returns entries whose parent matches", %{dir: dir} do
      assert Enum.map(RegionCatalog.children("gf:germany", dir), & &1.name) |> Enum.sort() ==
               ["bbbike:berlin", "gf:germany/bayern"]
    end

    test "search/2 matches label, name, and iso (case-insensitive)", %{dir: dir} do
      assert Enum.map(RegionCatalog.search("bayern", dir), & &1.name) == ["gf:germany/bayern"]
      assert Enum.map(RegionCatalog.search("DE-BY", dir), & &1.name) == ["gf:germany/bayern"]
      assert "gf:germany" in Enum.map(RegionCatalog.search("germ", dir), & &1.name)
    end
  end

  describe "tree_index/1" do
    setup %{dir: dir} do
      File.write!(Path.join(dir, "catalog.json"), Jason.encode!([
        %{"name" => "gf:europe", "label" => "Europe", "kind" => "continent", "parent" => nil, "pbf_url" => "x"},
        %{"name" => "gf:germany", "label" => "Germany", "kind" => "country", "parent" => "gf:europe", "pbf_url" => "x"},
        %{"name" => "gf:germany/bayern", "label" => "Bayern", "kind" => "subregion", "parent" => "gf:germany", "pbf_url" => "x"}
      ]))
      :ok
    end

    test "groups entries by parent, roots under nil", %{dir: dir} do
      index = RegionCatalog.tree_index(dir)

      assert Enum.map(index[nil], & &1.name) == ["gf:europe"]
      assert Enum.map(index["gf:europe"], & &1.name) == ["gf:germany"]
      assert Enum.map(index["gf:germany"], & &1.name) == ["gf:germany/bayern"]
    end

    test "child lists are sorted by label", %{dir: dir} do
      File.write!(Path.join(dir, "catalog.json"), Jason.encode!([
        %{"name" => "gf:europe", "label" => "Europe", "parent" => nil, "pbf_url" => "x"},
        %{"name" => "z", "label" => "Zeta", "parent" => "gf:europe", "pbf_url" => "x"},
        %{"name" => "a", "label" => "Alpha", "parent" => "gf:europe", "pbf_url" => "x"},
        %{"name" => "m", "label" => "Mu", "parent" => "gf:europe", "pbf_url" => "x"}
      ]))

      index = RegionCatalog.tree_index(dir)
      assert Enum.map(index["gf:europe"], & &1.label) == ["Alpha", "Mu", "Zeta"]
    end
  end

  describe "size_label/1 by kind" do
    test "uses the kind tier when bytes are nil; curated (kind nil) falls back to name hint" do
      country = %RegionCatalog{name: "gf:germany", label: "Germany", pbf_urls: [], pbf_bytes: nil, kind: "country"}
      continent = %RegionCatalog{name: "gf:europe", label: "Europe", pbf_urls: [], pbf_bytes: nil, kind: "continent"}
      subregion = %RegionCatalog{name: "gf:bayern", label: "Bayern", pbf_urls: [], pbf_bytes: nil, kind: "subregion"}
      city = %RegionCatalog{name: "bbbike:berlin", label: "Berlin", pbf_urls: [], pbf_bytes: nil, kind: "city"}
      preset = %RegionCatalog{name: "planet", label: "Planet", pbf_urls: [], pbf_bytes: nil, kind: nil}

      assert RegionCatalog.size_label(country) == "~75 GB"
      assert RegionCatalog.size_label(continent) == "~460 GB"
      assert RegionCatalog.size_label(subregion) == "~25 GB"
      assert RegionCatalog.size_label(city) == "~15 GB"
      assert RegionCatalog.size_label(preset) == "~1.1 TB"
    end
  end

  describe "all/1 dedupe-enrich" do
    test "collapses a curated preset and a baked entry sharing a PBF URL, adopting hierarchy", %{dir: dir} do
      File.write!(Path.join(dir, "germany.env"), """
      REGION_NAME=germany
      REGION_LABEL="Germany"
      PBF_URL=https://download.geofabrik.de/europe/germany-latest.osm.pbf
      """)

      File.write!(Path.join(dir, "europe.env"), """
      REGION_NAME=europe
      REGION_LABEL="Europe (continent)"
      PBF_URL=https://download.geofabrik.de/europe-latest.osm.pbf
      """)

      File.write!(Path.join(dir, "catalog.json"), Jason.encode!([
        %{"name" => "gf:europe", "label" => "Europe", "kind" => "continent", "parent" => nil,
          "pbf_url" => "https://download.geofabrik.de/europe-latest.osm.pbf"},
        %{"name" => "gf:germany", "label" => "Germany", "kind" => "country", "parent" => "gf:europe",
          "pbf_url" => "https://download.geofabrik.de/europe/germany-latest.osm.pbf",
          "pbf_bytes" => 4_776_095_728},
        %{"name" => "gf:bayern", "label" => "Bayern", "kind" => "subregion", "parent" => "gf:germany",
          "pbf_url" => "https://download.geofabrik.de/europe/germany/bayern-latest.osm.pbf"}
      ]))

      all = RegionCatalog.all(dir)
      by_name = Map.new(all, &{&1.name, &1})

      # one Germany, curated name kept, hierarchy adopted from the baked twin
      germanies = Enum.filter(all, &(&1.label == "Germany"))
      assert length(germanies) == 1
      [g] = germanies
      assert g.name == "germany"
      assert g.parent == "europe"
      assert g.kind == "country"
      assert g.pbf_bytes == 4_776_095_728
      assert RegionCatalog.size_label(g) == "4.8 GB"
      refute Map.has_key?(by_name, "gf:germany")
      refute Map.has_key?(by_name, "gf:europe")

      # the orphan-fix: bayern's parent is reparented from the dropped gf:germany
      # to the surviving curated name, so the chain europe→germany→bayern holds
      assert by_name["gf:bayern"].parent == "germany"
      assert by_name["europe"].parent == nil
    end
  end
end
