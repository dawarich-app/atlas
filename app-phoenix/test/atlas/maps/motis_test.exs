defmodule Atlas.Maps.MotisTest do
  use Atlas.DataCase, async: false
  alias Atlas.Maps.{Transit, Upstream.Client}

  setup do
    bypass = Bypass.open()
    old = System.get_env("MOTIS_URL")
    System.put_env("MOTIS_URL", "http://localhost:#{bypass.port}")

    on_exit(fn ->
      if old, do: System.put_env("MOTIS_URL", old), else: System.delete_env("MOTIS_URL")
    end)

    Atlas.Settings.set("transit_backend", "motis")
    {:ok, bypass: bypass}
  end

  test "routes through selected MOTIS, preserves walking, line names, times and polyline precision",
       %{bypass: bypass} do
    body = File.read!("test/fixtures/motis-plan.json")

    Bypass.expect_once(bypass, "GET", "/api/v6/plan", fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.params["useRoutedTransfers"] == "true"
      assert conn.params["arriveBy"] == "true"
      assert conn.params["time"] == "2026-09-07T08:00:00Z"
      Plug.Conn.resp(conn, 200, body)
    end)

    assert {:ok, result} =
             Transit.plan(
               from: %{lat: 52.4884438, lon: 13.4703145},
               to: %{lat: 52.5073, lon: 13.3324},
               arrive_by: true,
               datetime: "2026-09-07T10:00:00.641578+02:00"
             )

    [it] = result.features.itineraries
    assert it.transfers == 1
    assert it.walk_distance > 900
    assert Enum.map(it.legs, & &1.mode) == ~w(WALK RAIL WALK RAIL WALK)
    assert Enum.map(Enum.filter(it.legs, &(&1.mode == "RAIL")), & &1.route_name) == ~w(S85 S7)
    assert Enum.all?(it.legs, &(&1.shape_format == "google_polyline6"))
    [feature | _] = Atlas.Geometry.Coord.legs_to_geojson(it.legs).features
    [lon, lat] = hd(feature.geometry.coordinates)
    assert_in_delta lat, 52.4884438, 0.001
    assert_in_delta lon, 13.4703145, 0.001
  end

  test "direct walking is not presented as public transport", %{bypass: bypass} do
    Bypass.expect_once(bypass, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.params["time"] =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/
      Plug.Conn.resp(conn, 200, ~s({"itineraries":[],"direct":[{"legs":[{"mode":"WALK"}]}]}))
    end)

    assert {:ok, result} = Transit.plan(from: %{lat: 1, lon: 2}, to: %{lat: 3, lon: 4})
    assert result.features.itineraries == []
  end

  test "expired timetable error remains an error", %{bypass: bypass} do
    Bypass.expect_once(bypass, fn conn ->
      Plug.Conn.resp(conn, 400, ~s({"message":"outside timetable"}))
    end)

    assert {:error, %Client.BadResponse{status: 400}} =
             Transit.plan(from: %{lat: 1, lon: 2}, to: %{lat: 3, lon: 4})
  end
end
