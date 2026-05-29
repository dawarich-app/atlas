defmodule AtlasWeb.Api.V1.GeocodeControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    System.put_env("PHOTON_URL", "http://localhost:#{bypass.port}")
    System.put_env("PLACEHOLDER_URL", "http://localhost:#{bypass.port}")
    System.put_env("LIBPOSTAL_URL", "http://localhost:#{bypass.port}")
    on_exit(fn ->
      System.delete_env("PHOTON_URL")
      System.delete_env("PLACEHOLDER_URL")
      System.delete_env("LIBPOSTAL_URL")
    end)
    {:ok, bypass: bypass}
  end

  test "GET /api/v1/geocode?q=... returns forward array + mode=forward meta", %{conn: conn, bypass: bypass} do
    Bypass.expect(bypass, fn c ->
      case c.request_path do
        "/parser" -> Plug.Conn.resp(c, 200, ~s([{"label":"x","value":"berlin"}]))
        "/api" -> Plug.Conn.resp(c, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"Berlin"}}]}))
        "/parser/search" -> Plug.Conn.resp(c, 200, "[]")
      end
    end)

    resp = conn |> get(~p"/api/v1/geocode?q=berlin") |> json_response(200)
    assert is_list(resp["data"])
    assert [%{"name" => "Berlin"}] = resp["data"]
    assert resp["meta"]["mode"] == "forward"
    assert resp["meta"]["count"] == 1
    assert resp["meta"]["upstream"] == "ok"
  end

  test "GET /api/v1/geocode?lat=&lon=... returns reverse {here, admin} + mode=reverse meta", %{conn: conn, bypass: bypass} do
    Bypass.expect(bypass, fn c ->
      case c.request_path do
        "/reverse" -> Plug.Conn.resp(c, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"BG"}}]}))
        "/parser/search" -> Plug.Conn.resp(c, 200, "[]")
      end
    end)

    resp = conn |> get(~p"/api/v1/geocode?lat=52.5&lon=13.4") |> json_response(200)
    assert resp["data"]["here"]["name"] == "BG"
    assert is_map(resp["data"]["admin"])
    assert resp["meta"]["mode"] == "reverse"
    assert resp["meta"]["upstream"] == "ok"
  end

  test "GET /api/v1/geocode returns 400 without q or lat+lon", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/geocode") |> json_response(400)
    assert resp["error"]["code"] == "MISSING_PARAM"
  end
end
