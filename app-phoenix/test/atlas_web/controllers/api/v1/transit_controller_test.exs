defmodule AtlasWeb.Api.V1.TransitControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    System.put_env("OTP_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("OTP_URL") end)
    {:ok, bypass: bypass}
  end

  test "GET /api/v1/transit returns plan + ok", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/otp/routers/default/plan", fn c ->
      Plug.Conn.resp(c, 200, ~s({"plan":{"itineraries":[{"duration":600}]}}))
    end)

    resp = conn |> get(~p"/api/v1/transit?from=52.5,13.4&to=52.6,13.5") |> json_response(200)
    assert [%{"duration" => 600}] = resp["data"]["plan"]["itineraries"]
    assert resp["meta"]["upstream"] == "ok"
  end

  test "GET /api/v1/transit returns 400 without from/to", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/transit") |> json_response(400)
    assert resp["error"]["code"] == "MISSING_PARAM"
  end

  test "GET /api/v1/transit returns 422 VALIDATION_ERROR when to is unparseable", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/transit?from=52.5,13.4&to=garbage") |> json_response(422)
    assert resp["error"]["code"] == "VALIDATION_ERROR"
    assert resp["error"]["message"] =~ "to"
  end
end
