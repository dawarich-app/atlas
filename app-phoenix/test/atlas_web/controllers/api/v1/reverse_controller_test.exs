defmodule AtlasWeb.Api.V1.ReverseControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    Enum.each(["PHOTON_URL", "PLACEHOLDER_URL"], &System.put_env(&1, "http://localhost:#{bypass.port}"))
    on_exit(fn -> Enum.each(["PHOTON_URL", "PLACEHOLDER_URL"], &System.delete_env/1) end)
    {:ok, bypass: bypass}
  end

  test "GET /api/v1/reverse returns data + meta", %{conn: conn, bypass: bypass} do
    Bypass.expect(bypass, fn c ->
      case c.request_path do
        "/reverse" ->
          Plug.Conn.resp(c, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"BG","city":"Berlin","country":"Germany"}}]}))

        "/parser/search" ->
          Plug.Conn.resp(c, 200, "[]")
      end
    end)

    resp = conn |> get(~p"/api/v1/reverse?lat=52.5&lon=13.4") |> json_response(200)
    assert resp["data"]["here"]["name"] == "BG"
    assert resp["meta"]["upstream"] == "ok"
  end

  test "POST /api/v1/reverse/batch returns one result per coord", %{conn: conn, bypass: bypass} do
    Bypass.stub(bypass, "GET", "/reverse", fn c ->
      Plug.Conn.resp(c, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"X"}}]}))
    end)

    Bypass.stub(bypass, "GET", "/parser/search", fn c -> Plug.Conn.resp(c, 200, "[]") end)

    resp =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/reverse/batch", Jason.encode!(%{coords: [%{lat: 52.5, lon: 13.4}, %{lat: 48.1, lon: 11.5}]}))
      |> json_response(200)

    assert length(resp["data"]) == 2
    assert resp["meta"]["max_coords"] == 1000
    assert resp["meta"]["grid_precision"] == 6
  end

  test "GET /api/v1/reverse returns 400 without lat/lon", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/reverse") |> json_response(400)
    assert resp["error"]["code"] == "MISSING_PARAM"
  end

  test "POST /api/v1/reverse/batch returns 400 on coord missing lat", %{conn: conn} do
    resp =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/reverse/batch", Jason.encode!(%{coords: [%{lat: 52.5, lon: 13.4}, %{lon: 11.5}]}))
      |> json_response(400)

    assert resp["error"]["code"] == "INVALID_COORD"
    assert resp["error"]["message"] =~ "index 1"
  end

  test "POST /api/v1/reverse/batch returns 400 on coord with non-numeric lat", %{conn: conn} do
    resp =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/reverse/batch", Jason.encode!(%{coords: [%{lat: "abc", lon: 13.4}]}))
      |> json_response(400)

    assert resp["error"]["code"] == "INVALID_COORD"
  end
end
