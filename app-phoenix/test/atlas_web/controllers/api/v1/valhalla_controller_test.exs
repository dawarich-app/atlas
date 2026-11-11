defmodule AtlasWeb.Api.V1.ValhallaControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    System.put_env("VALHALLA_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("VALHALLA_URL") end)
    {:ok, bypass: bypass}
  end

  @request ~s({"locations":[{"lat":52.5,"lon":13.4},{"lat":52.52,"lon":13.42,"type":"through"},{"lat":52.6,"lon":13.5}],"costing":"bicycle","costing_options":{"bicycle":{"use_hills":0.1,"bicycle_type":"road"}},"alternates":2,"language":"de-DE"})

  test "GET /api/v1/valhalla/route hands Valhalla the query string verbatim and returns its body byte for byte",
       %{conn: conn, bypass: bypass} do
    query = "json=" <> URI.encode_www_form(@request)
    # Odd spacing and key order on purpose: a decode and re-encode would change them.
    body =
      ~s({"trip": {"summary":{"time":600,"length":1.2},"legs":[{"shape":"abc"}],"status":0,"language":"de-DE"},  "alternates":[{"trip":{"summary":{"time":660}}}],"id":null})

    Bypass.expect_once(bypass, "GET", "/route", fn c ->
      assert c.query_string == query
      Plug.Conn.resp(c, 200, body)
    end)

    conn = get(conn, "/api/v1/valhalla/route?" <> query)

    assert conn.status == 200
    assert conn.resp_body == body
    assert ["application/json" <> _] = get_resp_header(conn, "content-type")
  end

  test "GET /api/v1/valhalla/route passes Valhalla's refusals through with its own status and reason",
       %{conn: conn, bypass: bypass} do
    body =
      ~s({"error_code":171,"error":"No suitable edges near location","status_code":400,"status":"Bad Request"})

    Bypass.expect_once(bypass, "GET", "/route", fn c -> Plug.Conn.resp(c, 400, body) end)

    conn = get(conn, "/api/v1/valhalla/route?json=%7B%7D")

    assert conn.status == 400
    assert conn.resp_body == body
  end

  test "GET /api/v1/valhalla/route reaches only Valhalla's /route", %{conn: conn, bypass: bypass} do
    Bypass.stub(bypass, "GET", "/isochrone", fn _c -> flunk("only /route is mirrored") end)
    assert conn |> get("/api/v1/valhalla/isochrone?json=%7B%7D") |> Map.get(:status) == 404
    Bypass.pass(bypass)
  end

  test "GET /api/v1/valhalla/route is a 503 when Valhalla cannot be reached", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.down(bypass)
    resp = conn |> get("/api/v1/valhalla/route?json=%7B%7D") |> json_response(503)
    assert resp["error"]["code"] == "UPSTREAM_UNAVAILABLE"
  end
end
