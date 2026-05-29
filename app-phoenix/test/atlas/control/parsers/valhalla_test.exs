defmodule Atlas.Control.Parsers.ValhallaTest do
  use ExUnit.Case, async: true

  alias Atlas.Control.Parsers.LogReplay
  alias Atlas.Control.Parsers.Valhalla

  describe "Valhalla parser (log-fixture replay)" do
    test "parse fixture yields phase=parsing, not ready" do
      result = LogReplay.replay(Valhalla, LogReplay.fixture("valhalla-parse.log"))

      assert result.phase == "parsing"
      refute result.ready
    end

    test "tiles fixture (after parse+admins+elevation) yields phase=building-tiles" do
      result =
        LogReplay.replay_chain(Valhalla, [
          LogReplay.fixture("valhalla-parse.log"),
          LogReplay.fixture("valhalla-admins.log"),
          LogReplay.fixture("valhalla-elevation.log"),
          LogReplay.fixture("valhalla-tiles.log")
        ])

      assert result.phase == "building-tiles"
    end

    test "ready fixture (after tiles) yields phase=ready, ready=true" do
      result =
        LogReplay.replay_chain(Valhalla, [
          LogReplay.fixture("valhalla-tiles.log"),
          LogReplay.fixture("valhalla-ready.log")
        ])

      assert result.phase == "ready"
      assert result.ready
    end
  end
end
