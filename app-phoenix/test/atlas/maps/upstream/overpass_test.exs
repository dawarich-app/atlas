defmodule Atlas.Maps.Upstream.OverpassTest do
  use ExUnit.Case, async: true
  alias Atlas.Maps.Upstream.{Client, Overpass}

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, req: Client.build("http://localhost:#{bypass.port}")}
  end

  test "around/2 POSTs Overpass QL with around clause", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, "POST", "/api/interpreter", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "around:200,52.5,13.4"
      assert body =~ "[out:json]"
      Plug.Conn.resp(conn, 200, ~s({"elements":[]}))
    end)

    assert {:ok, %{"elements" => []}} = Overpass.around(req, lat: 52.5, lon: 13.4, radius: 200)
  end

  test "around/2 includes osm_tag filters when provided", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, "POST", "/api/interpreter", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ ~s(node["amenity"="cafe"])
      Plug.Conn.resp(conn, 200, ~s({"elements":[]}))
    end)

    Overpass.around(req, lat: 52.5, lon: 13.4, radius: 200, osm_tags: ["amenity:cafe"])
  end
end
