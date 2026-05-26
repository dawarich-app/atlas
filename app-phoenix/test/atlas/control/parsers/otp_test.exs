defmodule Atlas.Control.Parsers.OTPTest do
  use ExUnit.Case, async: true

  alias Atlas.Control.Parsers.LogReplay
  alias Atlas.Control.Parsers.OTP

  describe "OTP parser (log-fixture replay)" do
    test "osm fixture yields phase=loading-osm, not ready" do
      result = LogReplay.replay(OTP, LogReplay.fixture("otp-osm.log"))

      assert result.phase == "loading-osm"
      refute result.ready
    end

    test "graph fixture (after osm+gtfs) yields phase=building-graph" do
      result =
        LogReplay.replay_chain(OTP, [
          LogReplay.fixture("otp-osm.log"),
          LogReplay.fixture("otp-gtfs.log"),
          LogReplay.fixture("otp-graph.log")
        ])

      assert result.phase == "building-graph"
    end

    test "ready fixture (after graph) yields phase=ready, ready=true" do
      result =
        LogReplay.replay_chain(OTP, [
          LogReplay.fixture("otp-graph.log"),
          LogReplay.fixture("otp-ready.log")
        ])

      assert result.phase == "ready"
      assert result.ready
    end
  end
end
