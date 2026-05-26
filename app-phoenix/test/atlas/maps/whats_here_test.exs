defmodule Atlas.Maps.WhatsHereTest do
  use ExUnit.Case, async: false
  alias Atlas.Maps.{WhatsHere, Result}

  setup do
    bypass = Bypass.open()
    System.put_env("PHOTON_URL", "http://localhost:#{bypass.port}")
    System.put_env("PLACEHOLDER_URL", "http://localhost:#{bypass.port}")
    System.put_env("OVERPASS_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> ["PHOTON_URL","PLACEHOLDER_URL","OVERPASS_URL"] |> Enum.each(&System.delete_env/1) end)
    {:ok, bypass: bypass}
  end

  test "lookup fans out reverse and overpass in parallel", %{bypass: bypass} do
    Bypass.expect(bypass, fn conn ->
      case conn.request_path do
        "/reverse" -> Plug.Conn.resp(conn, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"BG"}}]}))
        "/api/interpreter" -> Plug.Conn.resp(conn, 200, ~s({"elements":[{"type":"node","id":1,"lat":52.5,"lon":13.4,"tags":{"amenity":"cafe"}}]}))
        "/parser/search" -> Plug.Conn.resp(conn, 200, "[]")
      end
    end)

    %Result{features: %{here: here, admin: _admin, nearby: [first_poi]}, upstream_status: "ok"} =
      WhatsHere.lookup(lat: 52.5, lon: 13.4, radius: 200)

    assert here.name == "BG"
    assert first_poi.id == "node/1"
    assert first_poi.tags == %{"amenity" => "cafe"}
  end

  test "lookup returns empty nearby when Overpass fails but reverse succeeds", %{bypass: bypass} do
    Bypass.expect(bypass, fn conn ->
      case conn.request_path do
        "/reverse" -> Plug.Conn.resp(conn, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"BG"}}]}))
        "/api/interpreter" -> Plug.Conn.resp(conn, 500, "boom")
        "/parser/search" -> Plug.Conn.resp(conn, 200, "[]")
      end
    end)

    %Result{features: %{nearby: nearby}, upstream_status: "ok"} = WhatsHere.lookup(lat: 52.5, lon: 13.4, radius: 200)
    assert nearby == []
  end
end
