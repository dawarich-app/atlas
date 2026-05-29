defmodule AtlasWeb.Api.V1.RouteControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    System.put_env("VALHALLA_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("VALHALLA_URL") end)
    {:ok, bypass: bypass}
  end

  test "GET /api/v1/route returns trip + ok", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/route", fn c ->
      Plug.Conn.resp(c, 200, ~s({"trip":{"summary":{"length":1.2}}}))
    end)

    resp = conn |> get(~p"/api/v1/route?from=52.5,13.4&to=52.6,13.5&mode=auto") |> json_response(200)
    assert resp["data"]["trip"]["summary"]["length"] == 1.2
    assert resp["meta"]["upstream"] == "ok"
  end

  test "GET /api/v1/route returns 400 without from/to", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/route") |> json_response(400)
    assert resp["error"]["code"] == "MISSING_PARAM"
  end
end
