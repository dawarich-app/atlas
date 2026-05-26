defmodule Atlas.Control.Parsers.WhosonfirstTest do
  use ExUnit.Case, async: true

  alias Atlas.Control.Parsers.LogReplay
  alias Atlas.Control.Parsers.Whosonfirst

  describe "Whosonfirst parser (log-fixture replay)" do
    test "download fixture yields phase=downloading, not ready" do
      result = LogReplay.replay(Whosonfirst, LogReplay.fixture("whosonfirst-download.log"))

      assert result.phase == "downloading"
      refute result.ready
    end

    test "complete fixture (after download) yields phase=complete, ready=true" do
      result =
        LogReplay.replay_chain(Whosonfirst, [
          LogReplay.fixture("whosonfirst-download.log"),
          LogReplay.fixture("whosonfirst-complete.log")
        ])

      assert result.phase == "complete"
      assert result.ready
    end
  end
end
