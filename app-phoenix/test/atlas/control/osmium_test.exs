defmodule Atlas.Control.OsmiumTest do
  use ExUnit.Case, async: false
  alias Atlas.Control.Osmium

  defp start_osmium(result) do
    test_pid = self()

    runner = fn cmd, args, opts ->
      send(test_pid, {:stub, cmd, args, opts})
      result
    end

    start_supervised!({Osmium, runner: runner})
  end

  test "merge/3 invokes native osmium merge inside data_dir" do
    start_osmium({"ok", 0})

    assert {:ok, "ok"} =
             Osmium.merge("/work/data/osm/sources", ["a.osm.pbf", "b.osm.pbf"], "../merged.osm.pbf")

    assert_received {:stub, "osmium", args, opts}

    assert args == ["merge", "a.osm.pbf", "b.osm.pbf", "-O", "-o", "../merged.osm.pbf"]
    assert opts[:cd] == "/work/data/osm/sources"
    assert opts[:stderr_to_stdout] == true
  end

  test "convert_to_osm_bz2/3 invokes native osmium cat with osm.bz2 format" do
    start_osmium({"ok", 0})

    assert {:ok, "ok"} = Osmium.convert_to_osm_bz2("/work/data/osm", "in.osm.pbf", "out.osm.bz2")

    assert_received {:stub, "osmium", args, opts}

    assert args == ["cat", "in.osm.pbf", "-o", "out.osm.bz2", "-O", "-f", "osm.bz2"]
    assert opts[:cd] == "/work/data/osm"
  end

  test "non-zero exit returns error with code and output" do
    start_osmium({"Open failed for 'a.osm.pbf'", 1})

    assert {:error, 1, "Open failed for 'a.osm.pbf'"} =
             Osmium.merge("/work/data/osm/sources", ["a.osm.pbf"], "out.osm.pbf")
  end
end
