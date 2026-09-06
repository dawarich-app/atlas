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
end
