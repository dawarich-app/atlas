defmodule AtlasWeb.Api.V1.PhotonControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    System.put_env("PHOTON_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("PHOTON_URL") end)
    {:ok, bypass: bypass}
  end

  test "GET /api/v1/photon/api forwards the query string verbatim and returns the raw body",
       %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/api", fn c ->
      # repeated osm_tag params must survive untouched — that's why we
      # forward the raw query string, not parsed params
      assert c.query_string == "q=berlin&limit=3&osm_tag=place&osm_tag=tourism"

      Plug.Conn.resp(
        c,
        200,
        ~s({"type":"FeatureCollection","features":[{"geometry":{"type":"Point","coordinates":[13.4,52.5]},"properties":{"osm_id":1,"osm_type":"R","osm_key":"place","osm_value":"city","extent":[13.0,52.3,13.8,52.7],"countrycode":"DE"}}]})
      )
    end)

    resp =
      conn
      |> get("/api/v1/photon/api?q=berlin&limit=3&osm_tag=place&osm_tag=tourism")
      |> json_response(200)

    assert resp["type"] == "FeatureCollection"
    assert [feature] = resp["features"]
    # full Photon fidelity: geometry, osm_* split, extent, countrycode all intact
    assert feature["geometry"]["coordinates"] == [13.4, 52.5]
    assert feature["properties"]["osm_key"] == "place"
    assert feature["properties"]["extent"] == [13.0, 52.3, 13.8, 52.7]
    assert feature["properties"]["countrycode"] == "DE"
  end

  test "GET /api/v1/photon/reverse forwards to Photon /reverse", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/reverse", fn c ->
      assert c.query_string == "lat=52.5&lon=13.4"
      Plug.Conn.resp(c, 200, ~s({"type":"FeatureCollection","features":[]}))
    end)

    resp = conn |> get("/api/v1/photon/reverse?lat=52.5&lon=13.4") |> json_response(200)
    assert resp["type"] == "FeatureCollection"
  end

  test "GET /api/v1/photon/lookup forwards to Photon /lookup", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/lookup", fn c ->
      assert c.query_string == "osm_id=1&osm_type=N"
      Plug.Conn.resp(c, 200, ~s({"features":[]}))
    end)

    assert conn |> get("/api/v1/photon/lookup?osm_id=1&osm_type=N") |> json_response(200)
  end

  test "GET /api/v1/photon/status forwards to Photon /status", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/status", fn c ->
      Plug.Conn.resp(c, 200, ~s({"status":"Ok","import_date":"2026-06-01T00:00:00Z"}))
    end)

    resp = conn |> get("/api/v1/photon/status") |> json_response(200)
    assert resp["status"] == "Ok"
  end

  test "Photon error statuses pass through verbatim", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/api", fn c ->
      Plug.Conn.resp(c, 400, ~s({"message":"missing search term"}))
    end)

    resp = conn |> get("/api/v1/photon/api") |> json_response(400)
    assert resp["message"] == "missing search term"
  end

  test "Photon down returns 503 UPSTREAM_UNAVAILABLE", %{conn: conn, bypass: bypass} do
    Bypass.down(bypass)
    resp = conn |> get("/api/v1/photon/api?q=berlin") |> json_response(503)
    assert resp["error"]["code"] == "UPSTREAM_UNAVAILABLE"
  end
end
