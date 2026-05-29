defmodule Atlas.Control.Parsers.PlaceholderTest do
  use ExUnit.Case, async: true

  alias Atlas.Control.Parsers.LogReplay
  alias Atlas.Control.Parsers.Placeholder

  describe "Placeholder parser (log-fixture replay)" do
    test "extract fixture yields phase=extracting, not ready" do
      result = LogReplay.replay(Placeholder, LogReplay.fixture("placeholder-extract.log"))

      assert result.phase == "extracting"
      refute result.ready
    end

    test "build fixture (after extract) yields phase=building, not ready" do
      result =
        LogReplay.replay_chain(Placeholder, [
          LogReplay.fixture("placeholder-extract.log"),
          LogReplay.fixture("placeholder-build.log")
        ])

      assert result.phase == "building"
      refute result.ready
    end

    test "ready fixture (after extract+build+optimize) yields phase=ready, ready=true" do
      result =
        LogReplay.replay_chain(Placeholder, [
          LogReplay.fixture("placeholder-extract.log"),
          LogReplay.fixture("placeholder-build.log"),
          LogReplay.fixture("placeholder-optimize.log"),
          LogReplay.fixture("placeholder-ready.log")
        ])

      assert result.phase == "ready"
      assert result.ready
    end
  end
end
