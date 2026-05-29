defmodule AtlasWeb.Api.V1.SearchControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    System.put_env("PHOTON_URL", "http://localhost:#{bypass.port}")
    System.put_env("PLACEHOLDER_URL", "http://localhost:#{bypass.port}")
    System.put_env("LIBPOSTAL_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> ["PHOTON_URL", "PLACEHOLDER_URL", "LIBPOSTAL_URL"] |> Enum.each(&System.delete_env/1) end)
    {:ok, bypass: bypass}
  end

  test "GET /api/v1/search returns 200 with envelope", %{conn: conn, bypass: bypass} do
    Bypass.expect(bypass, fn c ->
      case c.request_path do
        "/parser" -> Plug.Conn.resp(c, 200, "[]")
        "/api" -> Plug.Conn.resp(c, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"Berlin","city":"Berlin","country":"Germany","osm_id":1,"osm_type":"R","osm_key":"place","osm_value":"city"}}]}))
        "/parser/search" -> Plug.Conn.resp(c, 200, "[]")
      end
    end)

    resp = conn |> get(~p"/api/v1/search?q=berlin&limit=5") |> json_response(200)

    assert %{"data" => [%{"name" => "Berlin"}], "meta" => meta} = resp
    assert meta["upstream"] == "ok"
    assert meta["count"] == 1
  end

  test "GET /api/v1/search returns 400 MISSING_PARAM with details.param when q missing", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/search") |> json_response(400)
    assert resp["error"]["code"] == "MISSING_PARAM"
    assert resp["error"]["details"]["param"] == "q"
  end

  test "GET /api/v1/search returns 400 when q is blank", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/search?q=") |> json_response(400)
    assert resp["error"]["code"] == "MISSING_PARAM"
  end

  test "GET /api/v1/search returns 502 UPSTREAM_ERROR when Photon returns 5xx", %{conn: conn, bypass: bypass} do
    Bypass.expect(bypass, fn c ->
      case c.request_path do
        "/parser" -> Plug.Conn.resp(c, 200, "[]")
        "/api" -> Plug.Conn.resp(c, 500, "boom")
        "/parser/search" -> Plug.Conn.resp(c, 200, "[]")
      end
    end)

    resp = conn |> get(~p"/api/v1/search?q=berlin") |> json_response(502)
    assert resp["error"]["code"] == "UPSTREAM_ERROR"
  end

  test "GET /api/v1/search returns 503 UPSTREAM_UNAVAILABLE when Photon is down", %{conn: conn, bypass: bypass} do
    Bypass.down(bypass)
    resp = conn |> get(~p"/api/v1/search?q=berlin") |> json_response(503)
    assert resp["error"]["code"] == "UPSTREAM_UNAVAILABLE"
  end
end
