defmodule Atlas.Maps.Upstream.PhotonTest do
  use ExUnit.Case, async: true
  alias Atlas.Maps.Upstream.{Client, Photon}

  setup do
    bypass = Bypass.open()
    req = Client.build("http://localhost:#{bypass.port}")
    fixture = File.read!("test/fixtures/photon/search_berlin.json")
    {:ok, bypass: bypass, req: req, fixture: fixture}
  end

  test "search/2 hits /api with q, limit", %{bypass: bypass, req: req, fixture: fixture} do
    Bypass.expect_once(bypass, "GET", "/api", fn conn ->
      assert conn.query_string =~ "q=berlin"
      assert conn.query_string =~ "limit=10"
      Plug.Conn.resp(conn, 200, fixture) |> Plug.Conn.put_resp_content_type("application/json")
    end)

    assert {:ok, %{"features" => [_]}} = Photon.search(req, query: "berlin", limit: 10)
  end

  test "search/2 encodes osm_tags as repeated params (not Rails-style brackets)", %{bypass: bypass, req: req, fixture: fixture} do
    Bypass.expect_once(bypass, "GET", "/api", fn conn ->
      assert conn.query_string =~ "osm_tag=amenity%3Acafe"
      assert conn.query_string =~ "osm_tag=tourism%3Ahotel"
      refute conn.query_string =~ "osm_tag%5B%5D"
      Plug.Conn.resp(conn, 200, fixture)
    end)

    Photon.search(req, query: "x", limit: 5, osm_tags: ["amenity:cafe", "tourism:hotel"])
  end

  test "search/2 encodes bbox as comma-joined string", %{bypass: bypass, req: req, fixture: fixture} do
    Bypass.expect_once(bypass, "GET", "/api", fn conn ->
      assert conn.query_string =~ "bbox=13.0%2C52.0%2C14.0%2C53.0"
      Plug.Conn.resp(conn, 200, fixture)
    end)

    Photon.search(req, query: "x", limit: 5, bbox: [13.0, 52.0, 14.0, 53.0])
  end

  test "reverse/2 hits /reverse with lat,lon", %{bypass: bypass, req: req, fixture: fixture} do
    Bypass.expect_once(bypass, "GET", "/reverse", fn conn ->
      assert conn.query_string =~ "lat=52.52"
      assert conn.query_string =~ "lon=13.405"
      Plug.Conn.resp(conn, 200, fixture)
    end)

    Photon.reverse(req, lat: 52.52, lon: 13.405)
  end
end
