defmodule AtlasWeb.Api.V1.WhatsHereControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    System.put_env("PHOTON_URL", "http://localhost:#{bypass.port}")
    System.put_env("PLACEHOLDER_URL", "http://localhost:#{bypass.port}")
    System.put_env("OVERPASS_URL", "http://localhost:#{bypass.port}")

    on_exit(fn ->
      Enum.each(["PHOTON_URL", "PLACEHOLDER_URL", "OVERPASS_URL"], &System.delete_env/1)
    end)

    {:ok, bypass: bypass}
  end

  test "GET /api/v1/whats-here returns here + admin + nearby", %{conn: conn, bypass: bypass} do
    Bypass.expect(bypass, fn c ->
      case c.request_path do
        "/reverse" ->
          Plug.Conn.resp(c, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"BG","city":"Berlin","country":"Germany"}}]}))

        "/api/interpreter" ->
          Plug.Conn.resp(c, 200, ~s({"elements":[{"type":"node","id":1,"lat":52.5,"lon":13.4,"tags":{"amenity":"cafe"}}]}))

        "/parser/search" ->
          Plug.Conn.resp(c, 200, "[]")
      end
    end)

    resp = conn |> get(~p"/api/v1/whats-here?lat=52.5&lon=13.4&radius=300") |> json_response(200)

    assert resp["data"]["here"]["name"] == "BG"
    assert [%{"id" => "node/1"}] = resp["data"]["nearby"]
    assert resp["meta"]["upstream"] == "ok"
    assert resp["meta"]["radius"] == 300
  end

  test "GET /api/v1/whats-here returns 400 without lat/lon", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/whats-here") |> json_response(400)
    assert resp["error"]["code"] == "MISSING_PARAM"
  end

  test "GET /api/v1/whats-here returns 422 VALIDATION_ERROR when lat is non-numeric", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/whats-here?lat=abc&lon=13.4") |> json_response(422)
    assert resp["error"]["code"] == "VALIDATION_ERROR"
    assert resp["error"]["message"] =~ "lat"
  end
end
