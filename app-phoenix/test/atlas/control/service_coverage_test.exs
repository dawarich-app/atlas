defmodule Atlas.Control.ServiceCoverageTest do
  use ExUnit.Case, async: true
  alias Atlas.Control.{RegionCatalog, ServiceCoverage}

  @source "https://download.geofabrik.de/europe/germany/berlin-updates"
  @berlin %RegionCatalog{
    name: "berlin",
    label: "Berlin",
    pbf_urls: ["https://download.geofabrik.de/europe/germany/berlin-latest.osm.pbf"]
  }

  setup do
    dir = Path.join(System.tmp_dir!(), "coverage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp put(dir, path, contents) do
    dest = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(dest))
    File.write!(dest, contents)
  end

  test "reads the actual service input rather than other downloaded regions", %{dir: dir} do
    put(dir, "valhalla/region.osm.pbf", "berlin")
    put(dir, "osm/sources/antarctica.osm.pbf", "unrelated")

    result =
      ServiceCoverage.read("valhalla",
        data_dir: dir,
        catalog: [@berlin],
        probe: fn path ->
          assert path == Path.join(dir, "valhalla/region.osm.pbf")

          {:ok,
           %{
             "header" => %{
               "option" => %{"osmosis_replication_base_url" => @source},
               "boxes" => [[13, 52, 14, 53]]
             }
           }}
        end
      )

    assert [%{label: "Berlin", bounds: "13, 52, 14, 53"}] = result.entries
  end

  test "merged inputs retain each region and ignore stale provenance after replacement", %{
    dir: dir
  } do
    for path <- ~w(valhalla/region.osm.pbf otp/region.osm.pbf osm/current.osm.pbf),
        do: put(dir, path, "merged")

    bayern = %RegionCatalog{
      name: "bayern",
      label: "Bayern",
      pbf_urls: ["https://example.test/bayern.pbf"]
    }

    assert :ok = ServiceCoverage.record_inputs(dir, [@berlin, bayern])
    probe = fn _ -> {:error, :no_metadata} end
    opts = [data_dir: dir, catalog: [], probe: probe]
    assert Enum.map(ServiceCoverage.read("otp", opts).entries, & &1.label) == ["Berlin", "Bayern"]
    put(dir, "otp/region.osm.pbf", "replacement input")
    assert [%{label: "Region name unavailable"}] = ServiceCoverage.read("otp", opts).entries
  end

  test "reports missing data and unavailable metadata without guessing", %{dir: dir} do
    assert ServiceCoverage.read("otp", data_dir: dir, catalog: []).entries == []
    put(dir, "osm/current.osm.pbf", "input")

    result =
      ServiceCoverage.read("overpass",
        data_dir: dir,
        catalog: [],
        probe: fn _ -> raise "unavailable" end
      )

    assert result.entries == []
    assert result.note =~ "could not be read"
    assert ServiceCoverage.read("libpostal", data_dir: dir, catalog: []).note =~ "language model"
  end

  test "separates transit files from street coverage", %{dir: dir} do
    put(dir, "otp/vbb.gtfs.zip", "feed")
    put(dir, "gtfs/unrelated.gtfs.zip", "not staged")
    result = ServiceCoverage.read("otp", data_dir: dir, catalog: [])
    assert [%{label: "vbb.gtfs.zip", kind: "Transit timetable"}] = result.entries
  end

  test "keeps walking coverage when transit metadata contains malformed entries", %{dir: dir} do
    for path <- ~w(valhalla/region.osm.pbf otp/region.osm.pbf osm/current.osm.pbf),
        do: put(dir, path, "berlin")

    assert :ok = ServiceCoverage.record_inputs(dir, [@berlin])

    put(
      dir,
      "otp/atlas-sources.json",
      Jason.encode!([
        %{id: "vbb", name: "VBB", coverage: ""},
        "invalid",
        %{name: "Missing id"}
      ])
    )

    result = ServiceCoverage.read("otp", data_dir: dir, catalog: [@berlin])

    assert Enum.any?(result.entries, &(&1.kind == "Walking network" and &1.label == "Berlin"))

    assert Enum.any?(
             result.entries,
             &(&1.kind == "Transit timetable" and &1.source == "vbb")
           )
  end

  test "keeps walking coverage when transit metadata is invalid JSON", %{dir: dir} do
    for path <- ~w(valhalla/region.osm.pbf otp/region.osm.pbf osm/current.osm.pbf),
        do: put(dir, path, "berlin")

    assert :ok = ServiceCoverage.record_inputs(dir, [@berlin])
    put(dir, "otp/atlas-sources.json", "not json")

    result = ServiceCoverage.read("otp", data_dir: dir, catalog: [@berlin])

    assert [%{kind: "Walking network", label: "Berlin"}] = result.entries
  end

  test "photon requires a completed download and an index", %{dir: dir} do
    germany = "https://example.test/photon-db-germany-1.0-latest.tar.bz2"
    france = "https://example.test/photon-db-france-1.0-latest.tar.bz2"

    log =
      "Using constructed location for download: #{germany}\nSequential download process completed successfully.\nUsing constructed location for download: #{france}\nDownload failed\n"

    assert ServiceCoverage.photon_source(log) == germany

    assert ServiceCoverage.photon_source("Using constructed location for download: #{france}") ==
             nil

    put(dir, "photon/logs/photon.log", log)
    assert ServiceCoverage.read("photon", data_dir: dir, catalog: []).entries == []
    File.mkdir_p!(Path.join(dir, "photon/photon_data"))

    assert [%{label: "Germany", source: ^germany}] =
             ServiceCoverage.read("photon", data_dir: dir, catalog: []).entries
  end

  test "summarizes installed coverage by public capability", %{dir: dir} do
    for path <- ~w(valhalla/region.osm.pbf otp/region.osm.pbf osm/current.osm.pbf),
        do: put(dir, path, "berlin")

    assert :ok = ServiceCoverage.record_inputs(dir, [@berlin])

    photon_source = "https://example.test/photon-db-germany-1.0-latest.tar.bz2"

    put(
      dir,
      "photon/logs/photon.log",
      "Using constructed location for download: #{photon_source}\n" <>
        "Sequential download process completed successfully.\n"
    )

    File.mkdir_p!(Path.join(dir, "photon/photon_data"))

    put(
      dir,
      "otp/atlas-sources.json",
      Jason.encode!([%{id: "vbb", name: "VBB", coverage: "Berlin and Brandenburg"}])
    )

    result =
      ServiceCoverage.summary(
        data_dir: dir,
        catalog: [@berlin],
        valhalla_regions: "Germany",
        transit_backend: "otp",
        health: %{
          capabilities: %{
            "geocoding" => "up",
            "routing" => "up",
            "pois" => "down",
            "transit" => "up"
          }
        }
      )

    assert result.capabilities.geocoding.regions == ["Germany"]
    assert result.capabilities.routing.regions == ["Berlin"]
    assert result.capabilities.routing.available
    assert result.capabilities.map_matching.regions == ["Berlin"]
    assert result.capabilities.map_matching.inherits == "routing"
    refute result.capabilities.pois.available
    assert result.capabilities.transit.regions == ["Berlin"]

    assert result.capabilities.transit.transit_feeds == [
             %{
               name: "VBB",
               coverage: "Berlin and Brandenburg",
               evidence: "Connected source staged on disk; graph build required"
             }
           ]
  end

  test "uses declared Valhalla coverage when remote dataset provenance is unavailable", %{
    dir: dir
  } do
    result =
      ServiceCoverage.summary(
        data_dir: dir,
        valhalla_regions: " Germany, Europe, Germany,  ",
        transit_backend: "motis",
        health: %{capabilities: %{"routing" => "up"}}
      )

    assert result.capabilities.routing.regions == ["Germany", "Europe"]
    assert result.capabilities.routing.coverage_status == "known"
    assert result.capabilities.routing.available
    assert result.capabilities.map_matching.regions == ["Germany", "Europe"]
    assert result.capabilities.map_matching.inherits == "routing"

    assert Enum.map(result.capabilities.routing.datasets, & &1.label) == ["Germany", "Europe"]

    assert Enum.all?(
             result.capabilities.routing.datasets,
             &(&1.source == "VALHALLA_COVERAGE_REGIONS")
           )

    assert result.capabilities.routing.note =~ "declared by the operator"
  end

  test "public summary does not launch header probes for missing manifests", %{dir: dir} do
    for path <- ~w(valhalla/region.osm.pbf otp/region.osm.pbf osm/current.osm.pbf),
        do: put(dir, path, "not a real pbf")

    result =
      ServiceCoverage.summary(
        data_dir: dir,
        catalog: [@berlin],
        probe: fn _ -> flunk("summary must not execute an osmium probe") end,
        transit_backend: "otp",
        health: %{capabilities: %{}}
      )

    assert [%{evidence: "Input file present; metadata unavailable"}] =
             result.capabilities.routing.datasets

    assert result.capabilities.routing.coverage_status == "unknown"
  end

  test "blank provenance labels do not count as known coverage", %{dir: dir} do
    for path <- ~w(valhalla/region.osm.pbf otp/region.osm.pbf osm/current.osm.pbf),
        do: put(dir, path, "region")

    blank = %RegionCatalog{@berlin | label: "  "}
    assert :ok = ServiceCoverage.record_inputs(dir, [blank])

    result =
      ServiceCoverage.summary(
        data_dir: dir,
        transit_backend: "otp",
        health: %{capabilities: %{"routing" => "up"}}
      )

    assert result.capabilities.routing.regions == []
    assert result.capabilities.routing.coverage_status == "unknown"
  end
end
