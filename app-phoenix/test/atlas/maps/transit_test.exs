defmodule Atlas.Maps.TransitTest do
  use Atlas.DataCase, async: false
  alias Atlas.Maps.{Result, Transit}

  setup do
    bypass = Bypass.open()
    System.put_env("OTP_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("OTP_URL") end)
    Atlas.Settings.set("transit_backend", "otp")
    {:ok, bypass: bypass}
  end

  test "plan serializes itineraries to snake_case", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/otp/gtfs/v1", fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        ~s({"data":{"planConnection":{"edges":[{"node":{"start":1,"end":2,"duration":600,"walkDistance":50,"numberOfTransfers":1,"legs":[{"mode":"BUS","route":{"shortName":"M1"},"agency":{"name":"BVG"},"headsign":"H","start":1,"end":2,"duration":600,"distance":100,"from":{"name":"S","lat":52.5,"lon":13.4},"to":{"name":"T","lat":52.6,"lon":13.5},"legGeometry":{"points":"abc"}}]}}]}}})
      )
    end)

    assert {:ok, %Result{features: plan, upstream_status: "ok"}} =
             Transit.plan(from: %{lat: 52.5, lon: 13.4}, to: %{lat: 52.6, lon: 13.5})

    assert [it] = plan.itineraries
    assert it.start_time == 1
    assert it.walk_distance == 50
    assert it.transfers == 1
    assert [leg] = it.legs
    assert leg.mode == "BUS"
    assert leg.route_name == "M1"
    assert leg.agency_name == "BVG"
    assert leg.from == %{name: "S", lat: 52.5, lon: 13.4}
    assert leg.shape == "abc"
    assert leg.shape_format == "google_polyline5"
  end

  test "plan returns {:error, %Unavailable{}} when OTP down", %{bypass: bypass} do
    Bypass.down(bypass)

    assert {:error, %Atlas.Maps.Upstream.Client.Unavailable{}} =
             Transit.plan(from: %{lat: 0, lon: 0}, to: %{lat: 1, lon: 1})
  end
end
