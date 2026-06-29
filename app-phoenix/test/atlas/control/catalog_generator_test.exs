defmodule Atlas.Control.CatalogGeneratorTest do
  use ExUnit.Case, async: true
  alias Atlas.Control.CatalogGenerator

  @geofabrik %{
    "features" => [
      %{"properties" => %{"id" => "europe", "parent" => nil, "name" => "Europe",
        "urls" => %{"pbf" => "https://download.geofabrik.de/europe-latest.osm.pbf"}}},
      %{"properties" => %{"id" => "germany", "parent" => "europe", "name" => "Germany",
        "iso3166-1:alpha2" => ["DE"],
        "urls" => %{"pbf" => "https://download.geofabrik.de/europe/germany-latest.osm.pbf"}}},
      %{"properties" => %{"id" => "baden-wuerttemberg", "parent" => "germany", "name" => "Baden-Württemberg",
        "iso3166-2" => ["DE-BW"],
        "urls" => %{"pbf" => "https://download.geofabrik.de/europe/germany/baden-wuerttemberg-latest.osm.pbf"}}}
    ]
  }

  test "from_geofabrik/1 classifies continent/country/subregion and prefixes names" do
    entries = CatalogGenerator.from_geofabrik(@geofabrik)
    by_label = Map.new(entries, &{&1["label"], &1})

    assert by_label["Europe"]["name"] == "gf:europe"
    assert by_label["Europe"]["kind"] == "continent"
    assert by_label["Europe"]["parent"] == nil

    assert by_label["Germany"]["name"] == "gf:germany"
    assert by_label["Germany"]["kind"] == "country"
    assert by_label["Germany"]["parent"] == "gf:europe"
    assert by_label["Germany"]["country_code"] == "de"

    assert by_label["Baden-Württemberg"]["kind"] == "subregion"
    assert by_label["Baden-Württemberg"]["parent"] == "gf:germany"
    assert by_label["Baden-Württemberg"]["pbf_url"] =~ "baden-wuerttemberg-latest"
  end

  test "from_bbbike/1 builds city entries, parenting to country via override map" do
    entries = CatalogGenerator.from_bbbike(["Berlin", "Wien", "Atlantis"])
    by_label = Map.new(entries, &{&1["label"], &1})

    berlin = by_label["Berlin"]
    assert berlin["name"] == "bbbike:berlin"
    assert berlin["kind"] == "city"
    assert berlin["source"] == "bbbike"
    assert berlin["parent"] == "gf:germany"
    assert berlin["country_code"] == "de"
    assert berlin["pbf_url"] == "https://download.bbbike.org/osm/bbbike/Berlin/Berlin.osm.pbf"

    # Unknown city: no override -> floats at top level (parent nil), still selectable.
    assert by_label["Atlantis"]["parent"] == nil
    assert by_label["Atlantis"]["country_code"] == nil
  end

  test "enrich_sizes/2 fills pbf_bytes from head_fun and tolerates failures" do
    entries = [
      %{"name" => "gf:a", "pbf_url" => "https://x/a.pbf", "pbf_bytes" => nil},
      %{"name" => "gf:b", "pbf_url" => "https://x/b.pbf", "pbf_bytes" => nil}
    ]

    head_fun = fn
      "https://x/a.pbf" -> {:ok, 123}
      "https://x/b.pbf" -> {:error, :timeout}
    end

    [a, b] = CatalogGenerator.enrich_sizes(entries, head_fun)
    assert a["pbf_bytes"] == 123
    assert b["pbf_bytes"] == nil
  end

  test "validate/1 rejects dup names and unresolved parents" do
    good = [
      %{"name" => "gf:europe", "label" => "E", "kind" => "continent", "parent" => nil, "pbf_url" => "x"},
      %{"name" => "gf:de", "label" => "DE", "kind" => "country", "parent" => "gf:europe", "pbf_url" => "x"}
    ]
    assert CatalogGenerator.validate(good) == :ok

    dup = good ++ [%{"name" => "gf:de", "label" => "DE2", "kind" => "country", "parent" => "gf:europe", "pbf_url" => "x"}]
    assert {:error, msg} = CatalogGenerator.validate(dup)
    assert msg =~ "duplicate"

    orphan = [%{"name" => "gf:de", "label" => "DE", "kind" => "country", "parent" => "gf:nope", "pbf_url" => "x"}]
    assert {:error, msg2} = CatalogGenerator.validate(orphan)
    assert msg2 =~ "parent"
  end

  test "build/3 + write/2 produce a sorted, valid, round-trippable file" do
    geofabrik = %{"features" => [
      %{"properties" => %{"id" => "europe", "parent" => nil, "name" => "Europe", "urls" => %{"pbf" => "https://x/eu.pbf"}}},
      %{"properties" => %{"id" => "germany", "parent" => "europe", "name" => "Germany", "iso3166-1:alpha2" => ["DE"], "urls" => %{"pbf" => "https://x/de.pbf"}}}
    ]}

    entries = CatalogGenerator.build(geofabrik, ["Berlin"], fn _ -> {:ok, 10} end)
    assert CatalogGenerator.validate(entries) == :ok

    path = Path.join(System.tmp_dir!(), "catalog_#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm_rf!(path) end)
    :ok = CatalogGenerator.write(entries, path)

    decoded = path |> File.read!() |> Jason.decode!()
    assert Enum.map(decoded, & &1["name"]) == Enum.sort(Enum.map(decoded, & &1["name"]))
    assert Enum.any?(decoded, &(&1["name"] == "bbbike:berlin"))
    assert Enum.all?(decoded, &(&1["pbf_bytes"] == 10))
  end

  test "reconcile_parents/1 nulls parents that don't resolve, keeping the entry valid" do
    entries = [
      %{"name" => "gf:europe", "parent" => nil, "pbf_url" => "x"},
      %{"name" => "bbbike:wien", "parent" => "gf:austria", "pbf_url" => "x"},
      %{"name" => "gf:germany", "parent" => "gf:europe", "pbf_url" => "x"}
    ]

    reconciled = CatalogGenerator.reconcile_parents(entries)
    by_name = Map.new(reconciled, &{&1["name"], &1})

    assert by_name["bbbike:wien"]["parent"] == nil
    assert by_name["gf:germany"]["parent"] == "gf:europe"
    assert CatalogGenerator.validate(reconciled) == :ok
  end

  test "build/3 reconciles a bbbike city whose override country is absent from the index" do
    geofabrik = %{"features" => [
      %{"properties" => %{"id" => "europe", "parent" => nil, "name" => "Europe", "urls" => %{"pbf" => "https://x/eu.pbf"}}}
    ]}

    entries = CatalogGenerator.build(geofabrik, ["Wien"], fn _ -> {:error, :skipped} end)
    assert CatalogGenerator.validate(entries) == :ok
    wien = Enum.find(entries, &(&1["name"] == "bbbike:wien"))
    assert wien["parent"] == nil
  end
end
