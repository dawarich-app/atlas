defmodule Atlas.Control.Parsers.OverpassTest do
  use ExUnit.Case, async: true

  alias Atlas.Control.Parsers.LogReplay
  alias Atlas.Control.Parsers.Overpass

  describe "Overpass parser (log-fixture replay)" do
    test "download fixture yields phase=downloading, not ready" do
      result = LogReplay.replay(Overpass, LogReplay.fixture("overpass-download.log"))

      assert result.phase == "downloading"
      refute result.ready
    end

    test "ingest fixture (after download) yields phase=ingesting" do
      result =
        LogReplay.replay_chain(Overpass, [
          LogReplay.fixture("overpass-download.log"),
          LogReplay.fixture("overpass-ingest.log")
        ])

      assert result.phase == "ingesting"
    end

    test "ready fixture (after download+ingest) yields phase=ready, ready=true" do
      result =
        LogReplay.replay_chain(Overpass, [
          LogReplay.fixture("overpass-download.log"),
          LogReplay.fixture("overpass-ingest.log"),
          LogReplay.fixture("overpass-ready.log")
        ])

      assert result.phase == "ready"
      assert result.ready
    end
  end
end
