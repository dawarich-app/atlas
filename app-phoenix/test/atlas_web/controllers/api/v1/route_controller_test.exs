defmodule AtlasWeb.Api.V1.RouteControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    System.put_env("VALHALLA_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("VALHALLA_URL") end)
    {:ok, bypass: bypass}
  end

  test "GET /api/v1/route returns flat data + mode/options meta", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/route", fn c ->
      Plug.Conn.resp(c, 200, ~s({"trip":{"summary":{"length":1.2},"legs":[{"shape":"abc"}]}}))
    end)

    resp = conn |> get(~p"/api/v1/route?from=52.5,13.4&to=52.6,13.5&mode=auto") |> json_response(200)

    assert resp["data"]["summary"]["length"] == 1.2
    assert resp["data"]["shape_format"] == "valhalla_encoded_polyline6"
    assert [%{"shape" => "abc"}] = resp["data"]["legs"]
    refute Map.has_key?(resp["data"], "trip")

    assert resp["meta"]["mode"] == "auto"
    assert resp["meta"]["options"] == %{"avoid_tolls" => false, "avoid_highways" => false, "avoid_ferries" => false}
  end

  test "GET /api/v1/route returns 400 without from/to", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/route") |> json_response(400)
    assert resp["error"]["code"] == "MISSING_PARAM"
  end

  test "GET /api/v1/route returns 422 VALIDATION_ERROR when from is unparseable", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/route?from=garbage&to=52.6,13.5") |> json_response(422)
    assert resp["error"]["code"] == "VALIDATION_ERROR"
    assert resp["error"]["message"] =~ "from"
  end

  test "GET /api/v1/route returns 422 on invalid mode (not 500)", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/route?from=52.5,13.4&to=52.6,13.5&mode=teleport") |> json_response(422)
    assert resp["error"]["code"] == "VALIDATION_ERROR"
    assert resp["error"]["message"] =~ "mode"
  end

  test "GET /api/v1/route echoes avoidances in meta.options", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/route", fn c ->
      Plug.Conn.resp(c, 200, ~s({"trip":{"summary":{},"legs":[]}}))
    end)

    resp =
      conn
      |> get(~p"/api/v1/route?from=52.5,13.4&to=52.6,13.5&avoid_tolls=true&avoid_highways=1")
      |> json_response(200)

    assert resp["meta"]["options"]["avoid_tolls"] == true
    assert resp["meta"]["options"]["avoid_highways"] == true
    assert resp["meta"]["options"]["avoid_ferries"] == false
  end
end
