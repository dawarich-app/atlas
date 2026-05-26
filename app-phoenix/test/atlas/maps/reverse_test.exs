defmodule Atlas.Maps.ReverseTest do
  use ExUnit.Case, async: false
  alias Atlas.Maps.{Reverse, Result}

  setup do
    bypass = Bypass.open()
    photon_url = "http://localhost:#{bypass.port}"
    System.put_env("PHOTON_URL", photon_url)
    System.put_env("PLACEHOLDER_URL", photon_url)
    on_exit(fn -> System.delete_env("PHOTON_URL") end)
    {:ok, bypass: bypass}
  end

  test "lookup returns feature + admin + ok status", %{bypass: bypass} do
    Bypass.expect(bypass, fn conn ->
      case conn.request_path do
        "/reverse" -> Plug.Conn.resp(conn, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"osm_id":1,"osm_type":"N","name":"Brandenburg Gate","city":"Berlin","country":"Germany"}}]}))
        "/parser/search" -> Plug.Conn.resp(conn, 200, "[]")
      end
    end)

    assert %Result{features: %{here: feature, admin: admin}, upstream_status: "ok"} =
             Reverse.lookup(lat: 52.5, lon: 13.4)

    assert feature.name == "Brandenburg Gate"
    assert admin.city == "Berlin"
  end

  test "lookup returns unavailable when Photon down", %{bypass: bypass} do
    Bypass.down(bypass)
    assert %Result{upstream_status: "unavailable"} = Reverse.lookup(lat: 52.5, lon: 13.4)
  end
end
