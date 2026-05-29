defmodule AtlasWeb.Api.V1.GeocodeControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    System.put_env("PHOTON_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("PHOTON_URL") end)
    {:ok, bypass: bypass}
  end

  test "GET /api/v1/geocode returns first feature + ok", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/api", fn c ->
      Plug.Conn.resp(c, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"Berlin"}}]}))
    end)

    resp = conn |> get(~p"/api/v1/geocode?q=berlin") |> json_response(200)
    assert resp["data"]["name"] == "Berlin"
    assert resp["meta"]["upstream"] == "ok"
  end

  test "GET /api/v1/geocode returns 400 without q", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/geocode") |> json_response(400)
    assert resp["error"]["code"] == "MISSING_PARAM"
    assert resp["error"]["details"]["param"] == "q"
  end
end
