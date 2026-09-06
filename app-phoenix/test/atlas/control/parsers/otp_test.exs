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

  describe "a whole real build (unabridged container log)" do
    # otp-full-build.log is a verbatim capture of one container start, from
    # config load to "Grizzly server running". The hand-written fixtures above
    # once agreed with a @ready_re that matched no line OTP emits — every
    # pattern was a plausible paraphrase, and the suite stayed green while the
    # UI sat at 90% forever. Only unedited output can catch that.
    setup do
      path = LogReplay.fixture("otp-full-build.log")
      {:ok, path: path, lines: path |> File.read!() |> String.split("\n", trim: true)}
    end

    test "reaches ready without any API traffic", %{path: path} do
      result = LogReplay.replay(OTP, path)

      assert result.phase == "ready"
      assert result.ready
      assert result.progress == 1.0
    end

    test "reaches ready on the server's own output, not on a served request", %{
      path: path,
      lines: lines
    } do
      # @serve_re ("GET /otp/") would otherwise mask a broken @ready_re the
      # moment anything queried the API — which is exactly how this hid.
      refute Enum.any?(lines, &(&1 =~ "GET /otp/")),
             "fixture must contain no API traffic, or it cannot prove @ready_re works"

      assert LogReplay.replay(OTP, path).ready
    end

    test "passes through the build phases in order", %{lines: lines} do
      phases =
        lines
        |> Enum.scan(OTP.init(), fn line, acc -> elem(OTP.feed(line, acc), 1) end)
        |> Enum.map(& &1.phase)
        |> Enum.dedup()
        |> Enum.reject(&is_nil/1)

      assert phases ==
               ~w(loading-osm building-graph loading-gtfs trip-patterns saving-graph ready)
    end

    test "never reports an error phase on a healthy build", %{lines: lines} do
      states = Enum.scan(lines, OTP.init(), fn line, acc -> elem(OTP.feed(line, acc), 1) end)

      refute Enum.any?(states, &(&1.phase == "error")),
             "a clean build must not trip @error_re on OTP's routine data-quality ERROR lines"
    end
  end
end
