defmodule Atlas.Control.OsmiumTest do
  use ExUnit.Case, async: false
  alias Atlas.Control.Osmium

  setup do
    test_pid = self()
    runner = fn cmd, args ->
      send(test_pid, {:stub, cmd, args})
      {"ok", 0}
    end

    {:ok, pid} = start_supervised({Osmium, runner: runner})
    {:ok, pid: pid}
  end

  test "merge/3 invokes docker run with osmium merge args" do
    assert {0, "ok"} = Osmium.merge("/data/photon", ["a.osm.pbf", "b.osm.pbf"], "merged.osm.pbf")

    assert_received {:stub, "docker", args}

    assert args == [
             "run", "--rm",
             "-v", "/data/photon:/data",
             "-w", "/data",
             "stefda/osmium-tool",
             "osmium", "merge",
             "a.osm.pbf", "b.osm.pbf",
             "-O", "-o", "merged.osm.pbf"
           ]
  end

  test "convert_to_osm_bz2/3 invokes osmium cat with osm.bz2 format" do
    assert {0, "ok"} = Osmium.convert_to_osm_bz2("/data/overpass", "in.osm.pbf", "out.osm.bz2")

    assert_received {:stub, "docker", args}

    assert args == [
             "run", "--rm",
             "-v", "/data/overpass:/data",
             "-w", "/data",
             "stefda/osmium-tool",
             "osmium", "cat", "in.osm.pbf",
             "-o", "out.osm.bz2",
             "-O", "-f", "osm.bz2"
           ]
  end
end
