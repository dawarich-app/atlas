defmodule AtlasWeb.Api.V1.TransitControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    System.put_env("OTP_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("OTP_URL") end)
    {:ok, bypass: bypass}
  end

  test "GET /api/v1/transit returns serialized plan + meta with modes/num/time", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/otp/routers/default/plan", fn c ->
      Plug.Conn.resp(c, 200, ~s({"plan":{"itineraries":[{"duration":600,"legs":[]}]}}))
    end)

    resp =
      conn
      |> get(~p"/api/v1/transit?from=52.5,13.4&to=52.6,13.5&num=2&modes=TRANSIT")
      |> json_response(200)

    assert [%{"duration" => 600}] = resp["data"]["itineraries"]
    assert resp["meta"]["upstream"] == "ok"
    assert resp["meta"]["modes"] == "TRANSIT"
    assert resp["meta"]["num"] == 2
    assert is_binary(resp["meta"]["time"])
  end

  test "GET /api/v1/transit clamps num to 1..6", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/otp/routers/default/plan", fn c ->
      assert URI.decode_query(c.query_string)["numItineraries"] == "6"
      Plug.Conn.resp(c, 200, ~s({"plan":{"itineraries":[]}}))
    end)

    resp = conn |> get(~p"/api/v1/transit?from=52.5,13.4&to=52.6,13.5&num=99") |> json_response(200)
    assert resp["meta"]["num"] == 6
  end

  test "GET /api/v1/transit accepts ISO8601 time and forwards date+time to OTP", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/otp/routers/default/plan", fn c ->
      q = URI.decode_query(c.query_string)
      assert q["date"] == "2026-05-29"
      assert String.starts_with?(q["time"], "08:30")
      Plug.Conn.resp(c, 200, ~s({"plan":{"itineraries":[]}}))
    end)

    resp = conn |> get(~p"/api/v1/transit?from=52.5,13.4&to=52.6,13.5&time=2026-05-29T08:30:00Z") |> json_response(200)
    assert resp["meta"]["time"] =~ "2026-05-29"
  end

  test "GET /api/v1/transit defaults modes to TRANSIT,WALK", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/otp/routers/default/plan", fn c ->
      assert URI.decode_query(c.query_string)["mode"] == "TRANSIT,WALK"
      Plug.Conn.resp(c, 200, ~s({"plan":{"itineraries":[]}}))
    end)

    resp = conn |> get(~p"/api/v1/transit?from=52.5,13.4&to=52.6,13.5") |> json_response(200)
    assert resp["meta"]["modes"] == "TRANSIT,WALK"
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
