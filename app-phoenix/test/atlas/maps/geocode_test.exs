defmodule Atlas.Maps.GeocodeTest do
  use ExUnit.Case, async: false
  alias Atlas.Maps.{Geocode, Result}

  setup do
    bypass = Bypass.open()
    System.put_env("PHOTON_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("PHOTON_URL") end)
    {:ok, bypass: bypass}
  end

  test "lookup returns first feature on Photon success", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/api", fn conn -> Plug.Conn.resp(conn, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"X"}}]})) end)
    assert %Result{features: feature, upstream_status: "ok"} = Geocode.lookup(query: "X")
    assert feature.name == "X"
  end

  test "lookup returns nil + unavailable when down", %{bypass: bypass} do
    Bypass.down(bypass)
    assert %Result{features: nil, upstream_status: "unavailable"} = Geocode.lookup(query: "X")
  end
end
