defmodule AtlasWeb.Api.V1.TransitControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    System.put_env("OTP_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("OTP_URL") end)
    Atlas.Settings.set("transit_backend", "otp")
    {:ok, bypass: bypass}
  end

  test "GET /api/v1/transit returns serialized plan + meta with modes/time", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "POST", "/otp/gtfs/v1", fn c ->
      {:ok, body, c} = Plug.Conn.read_body(c)
      assert Jason.decode!(body)["query"] =~ "planConnection"

      Plug.Conn.resp(
        c,
        200,
        ~s({"data":{"planConnection":{"edges":[{"node":{"duration":600,"legs":[]}}]}}})
      )
    end)

    resp =
      conn
      |> get(~p"/api/v1/transit?from=52.5,13.4&to=52.6,13.5&num=2&modes=TRANSIT")
      |> json_response(200)

    assert [%{"duration" => 600}] = resp["data"]["itineraries"]
    assert resp["meta"]["modes"] == "TRANSIT"
    assert is_binary(resp["meta"]["time"])
  end

  test "GET /api/v1/transit clamps num to 1..6", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/otp/gtfs/v1", fn c ->
      {:ok, body, c} = Plug.Conn.read_body(c)
      assert Jason.decode!(body)["query"] =~ "planConnection"
      Plug.Conn.resp(c, 200, ~s({"data":{"planConnection":{"edges":[]}}}))
    end)

    resp =
      conn |> get(~p"/api/v1/transit?from=52.5,13.4&to=52.6,13.5&num=99") |> json_response(200)

    assert resp["data"]["itineraries"] == []
  end

  test "GET /api/v1/transit accepts ISO8601 time and forwards date+time to OTP", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "POST", "/otp/gtfs/v1", fn c ->
      {:ok, body, c} = Plug.Conn.read_body(c)
      date_time = Jason.decode!(body)["variables"]["dateTime"]
      assert date_time == %{"earliestDeparture" => "2026-05-29T08:30:00Z"}
      Plug.Conn.resp(c, 200, ~s({"data":{"planConnection":{"edges":[]}}}))
    end)

    resp =
      conn
      |> get(~p"/api/v1/transit?from=52.5,13.4&to=52.6,13.5&time=2026-05-29T08:30:00Z")
      |> json_response(200)

    assert resp["meta"]["time"] =~ "2026-05-29"
  end

  test "GET /api/v1/transit defaults modes to TRANSIT,WALK", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/otp/gtfs/v1", fn c ->
      {:ok, body, c} = Plug.Conn.read_body(c)
      variables = Jason.decode!(body)["variables"]
      assert variables["modes"]["direct"] == ["WALK"]
      assert Enum.any?(variables["modes"]["transit"]["transit"], &(&1["mode"] == "BUS"))
      Plug.Conn.resp(c, 200, ~s({"data":{"planConnection":{"edges":[]}}}))
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
