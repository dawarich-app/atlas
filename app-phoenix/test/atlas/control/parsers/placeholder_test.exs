defmodule Atlas.Control.Parsers.PlaceholderTest do
  use ExUnit.Case, async: true

  alias Atlas.Control.Parsers.LogReplay
  alias Atlas.Control.Parsers.Placeholder

  test "database bootstrap reports downloading until the server is listening" do
    {downloading, acc} = Placeholder.feed("[placeholder] downloaded 64 MiB", Placeholder.init())
    assert downloading.phase == "downloading"
    refute downloading.ready
    {ready, _acc} = Placeholder.feed("[placeholder] [worker 24] listening on 0.0.0.0:3000", acc)
    assert ready.ready
  end

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
