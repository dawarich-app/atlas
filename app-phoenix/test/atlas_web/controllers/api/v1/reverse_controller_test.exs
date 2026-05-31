defmodule AtlasWeb.Api.V1.ReverseControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    Cachex.clear(:reverse_cache)
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

  test "POST /api/v1/reverse/batch returns one result per coord with new caps", %{conn: conn, bypass: bypass} do
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
    assert resp["meta"]["max_coords"] == 500
    assert resp["meta"]["grid_precision"] == 4
  end

  test "GET /api/v1/reverse returns 400 without lat/lon", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/reverse") |> json_response(400)
    assert resp["error"]["code"] == "MISSING_PARAM"
  end

  test "GET /api/v1/reverse returns 422 VALIDATION_ERROR when lat non-numeric", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/reverse?lat=abc&lon=13.4") |> json_response(422)
    assert resp["error"]["code"] == "VALIDATION_ERROR"
    assert resp["error"]["message"] =~ "lat"
  end

  test "POST /api/v1/reverse/batch returns 422 when over MAX_COORDS=500", %{conn: conn} do
    coords = for n <- 1..501, do: %{lat: 52.0 + n / 10000, lon: 13.0 + n / 10000}

    resp =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/reverse/batch", Jason.encode!(%{coords: coords}))
      |> json_response(422)

    assert resp["error"]["code"] == "VALIDATION_ERROR"
    assert resp["error"]["details"]["max"] == 500
  end

  test "POST /api/v1/reverse/batch per-item bad input is reported inline, not halting", %{conn: conn, bypass: bypass} do
    Bypass.stub(bypass, "GET", "/reverse", fn c ->
      Plug.Conn.resp(c, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"X"}}]}))
    end)

    Bypass.stub(bypass, "GET", "/parser/search", fn c -> Plug.Conn.resp(c, 200, "[]") end)

    resp =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/reverse/batch", Jason.encode!(%{coords: [%{lat: 52.5, lon: 13.4, id: "a"}, %{lat: "abc", lon: 13.4, id: "b"}]}))
      |> json_response(200)

    assert [r1, r2] = resp["data"]
    assert r1["id"] == "a"
    assert is_map(r1["here"])

    assert r2["id"] == "b"
    assert r2["error"] =~ "numeric"
    assert r2["coord"]["raw_lat"] == "abc"
  end

  test "POST /api/v1/reverse/batch echoes per-coord id", %{conn: conn, bypass: bypass} do
    Bypass.stub(bypass, "GET", "/reverse", fn c ->
      Plug.Conn.resp(c, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"X"}}]}))
    end)

    Bypass.stub(bypass, "GET", "/parser/search", fn c -> Plug.Conn.resp(c, 200, "[]") end)

    resp =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/reverse/batch", Jason.encode!(%{coords: [%{lat: 52.5, lon: 13.4, id: "p1"}]}))
      |> json_response(200)

    assert [%{"id" => "p1"}] = resp["data"]
  end
end
