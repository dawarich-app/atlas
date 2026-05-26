defmodule Atlas.Control.Parsers.PhotonTest do
  use ExUnit.Case, async: true

  alias Atlas.Control.Parsers.LogReplay
  alias Atlas.Control.Parsers.Photon

  describe "Photon parser (log-fixture replay)" do
    test "download fixture yields phase=downloading, progress=0.125, not ready" do
      result = LogReplay.replay(Photon, LogReplay.fixture("photon-download.log"))

      assert result.phase == "downloading"
      assert_in_delta result.progress, 0.125, 0.0001
      refute result.ready
    end

    test "extract fixture (after download) yields phase=extracting, not ready" do
      result =
        LogReplay.replay_chain(Photon, [
          LogReplay.fixture("photon-download.log"),
          LogReplay.fixture("photon-extract.log")
        ])

      assert result.phase == "extracting"
      refute result.ready
    end

    test "ready fixture (after download + extract) yields phase=ready, ready=true" do
      result =
        LogReplay.replay_chain(Photon, [
          LogReplay.fixture("photon-download.log"),
          LogReplay.fixture("photon-extract.log"),
          LogReplay.fixture("photon-ready.log")
        ])

      assert result.phase == "ready"
      assert result.ready
    end
  end
end
