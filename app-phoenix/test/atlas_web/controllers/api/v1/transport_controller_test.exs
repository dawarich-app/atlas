defmodule AtlasWeb.Api.V1.TransportControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    previous = System.get_env("MOTIS_URL")
    System.put_env("MOTIS_URL", "http://localhost:#{bypass.port}")

    on_exit(fn ->
      if previous, do: System.put_env("MOTIS_URL", previous), else: System.delete_env("MOTIS_URL")
    end)

    Atlas.Settings.set("transit_backend", "motis")
    {:ok, bypass: bypass}
  end

  test "stops translate lon/lat bbox, avoid optional grouped index, and cap output", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "GET", "/api/v6/map/stops", fn c ->
      c = Plug.Conn.fetch_query_params(c)
      assert c.query_params == %{"min" => "52.5,13.4", "max" => "52.51,13.42"}
      Plug.Conn.resp(c, 200, Jason.encode!(Enum.map(1..1001, &%{stopId: "stop-#{&1}"})))
    end)

    result =
      conn |> get("/api/v1/transport/stops?bbox=13.4,52.5,13.42,52.51") |> json_response(200)

    assert length(result["data"]) == 1000
    assert result["meta"]["truncated"]
    assert is_binary(result["meta"]["timestamp"])
  end

  test "lines request the next hour with polyline5 and deduplicate service shapes", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "GET", "/api/v6/map/trips", fn c ->
      c = Plug.Conn.fetch_query_params(c)
      assert c.query_params["precision"] == "5"
      assert c.query_params["zoom"] == "15"
      {:ok, from, 0} = DateTime.from_iso8601(c.query_params["startTime"])
      {:ok, to, 0} = DateTime.from_iso8601(c.query_params["endTime"])
      assert DateTime.diff(to, from) == 3600
      assert from.microsecond == {0, 0}
      line = %{polyline: "test", mode: "BUS", trips: [%{displayName: "100"}]}
      Plug.Conn.resp(c, 200, Jason.encode!([line, line]))
    end)

    result =
      conn
      |> get("/api/v1/transport/lines?bbox=13.4,52.5,13.42,52.51&zoom=15")
      |> json_response(200)

    assert length(result["data"]) == 1
    refute result["meta"]["truncated"]
  end

  test "dense city areas retain stops and request zooming instead of failing the entire layer", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "GET", "/api/v6/map/trips", fn c ->
      Plug.Conn.resp(c, 422, ~s({"error":"too many trips"}))
    end)

    result =
      conn
      |> get("/api/v1/transport/lines?bbox=13.4,52.5,13.42,52.51&zoom=11")
      |> json_response(200)

    assert result["data"] == []
    assert result["meta"]["truncated"]
    assert result["meta"]["zoom_in"]
  end

  test "departure board encodes platform IDs and retains only the queried platform with second-precision time",
       %{
         conn: conn,
         bypass: bypass
       } do
    Bypass.expect_once(bypass, "GET", "/api/v6/stoptimes", fn c ->
      c = Plug.Conn.fetch_query_params(c)
      assert c.query_params["stopId"] == "vbb_stop:1/2"
      assert c.query_params["n"] == "20"
      assert c.query_params["radius"] == "1"
      assert c.query_params["exactRadius"] == "true"
      refute Map.has_key?(c.query_params, "window")
      assert {:ok, %{microsecond: {0, 0}}, 0} = DateTime.from_iso8601(c.query_params["time"])

      board = %{
        place: %{stopId: "vbb_stop:1/2"},
        stopTimes: [
          %{place: %{stopId: "vbb_stop:1/3"}, displayName: "U2"},
          %{
            place: %{
              stopId: "vbb_stop:1/2",
              scheduledDeparture: "2026-11-28T09:00:00Z",
              departure: "2026-11-28T09:05:00Z",
              scheduledTrack: "1",
              track: "3"
            },
            displayName: "U5",
            realTime: true,
            tripCancelled: false
          }
        ]
      }

      Plug.Conn.resp(c, 200, Jason.encode!(board))
    end)

    conn = get(conn, "/api/v1/transport/departures?stop_id=vbb_stop%3A1%2F2")
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    result = json_response(conn, 200)

    assert [%{"displayName" => "U5", "realTime" => true, "place" => place}] =
             result["data"]["stopTimes"]

    assert place["scheduledDeparture"] == "2026-11-28T09:00:00Z"
    assert place["departure"] == "2026-11-28T09:05:00Z"
    assert place["scheduledTrack"] == "1"
    assert place["track"] == "3"
  end

  test "trip requests detailed intermediate stops", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/api/v6/trip", fn c ->
      c = Plug.Conn.fetch_query_params(c)
      assert c.query_params == %{"tripId" => "20261122_service", "detailedLegs" => "true"}
      Plug.Conn.resp(c, 200, ~s({"legs":[]}))
    end)

    assert %{"data" => %{"legs" => []}} =
             conn |> get("/api/v1/transport/trip?trip_id=20261122_service") |> json_response(200)
  end

  test "rejects absent, malformed, out-of-range, reversed, and excessive areas before upstream requests",
       %{conn: conn} do
    assert conn |> get("/api/v1/transport/stops") |> json_response(400)

    for box <- [
          "13.4x,52.5,13.42,52.51",
          "13.42,52.5,13.4,52.51",
          "181,52,182,53",
          "13,52,14,53",
          "-180,52,180,52.00001",
          "a,b,c,d"
        ] do
      assert conn |> get("/api/v1/transport/stops?bbox=#{URI.encode(box)}") |> json_response(422)
    end

    for zoom <- ["abc", "10", "19", "15junk"] do
      assert conn
             |> get("/api/v1/transport/lines?bbox=13.4,52.5,13.42,52.51&zoom=#{zoom}")
             |> json_response(422)
    end

    assert conn |> get("/api/v1/transport/departures") |> json_response(400)

    assert conn
           |> get("/api/v1/transport/trip?trip_id=#{String.duplicate("a", 513)}")
           |> json_response(422)
  end

  test "OTP deployments explicitly report unsupported transport layer", %{conn: conn} do
    Atlas.Settings.set("transit_backend", "otp")

    result =
      conn |> get("/api/v1/transport/stops?bbox=13.4,52.5,13.42,52.51") |> json_response(501)

    assert result["error"]["code"] == "TRANSPORT_UNSUPPORTED"
  end

  test "upstream errors and unexpected successful payloads are structured 502 responses", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "GET", "/api/v6/map/stops", fn c ->
      Plug.Conn.resp(c, 500, "failed")
    end)

    assert conn |> get("/api/v1/transport/stops?bbox=13.4,52.5,13.42,52.51") |> json_response(502)

    Bypass.expect_once(bypass, "GET", "/api/v6/stoptimes", fn c ->
      Plug.Conn.resp(c, 200, ~s({"unexpected":true}))
    end)

    assert conn |> get("/api/v1/transport/departures?stop_id=stop") |> json_response(502)
  end
end
