defmodule Atlas.Maps.PoiTest do
  use ExUnit.Case, async: false
  alias Atlas.Maps.{Poi, Result}

  setup do
    bypass = Bypass.open()
    System.put_env("OVERPASS_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("OVERPASS_URL") end)
    {:ok, bypass: bypass}
  end

  test "catalog/0 returns the list of categories" do
    catalog = Poi.catalog()
    assert is_list(catalog)
    assert length(catalog) > 0
    [first | _] = catalog
    assert Map.has_key?(first, :key)
    assert Map.has_key?(first, :label)
    assert Map.has_key?(first, :osm_tags)
  end

  test "nearby/1 with category resolves osm_tags from catalog and queries Overpass", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/interpreter", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ ~s|["amenity"="restaurant"]|
      Plug.Conn.resp(conn, 200, ~s({"elements":[]}))
    end)

    assert %Result{features: [], upstream_status: "ok"} =
             Poi.nearby(lat: 52.5, lon: 13.4, radius: 500, category: "food")
  end

  test "nearby/1 returns empty list and error status when category unknown" do
    assert %Result{features: [], upstream_status: "error"} =
             Poi.nearby(lat: 52.5, lon: 13.4, radius: 500, category: "does-not-exist")
  end
end
