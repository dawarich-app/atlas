defmodule Atlas.Maps.PoiTest do
  use ExUnit.Case, async: false
  alias Atlas.Maps.{Poi, Result}

  setup do
    bypass = Bypass.open()
    System.put_env("OVERPASS_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("OVERPASS_URL") end)
    {:ok, bypass: bypass}
  end

  test "catalog/0 returns nested sections-with-items" do
    [first | _] = Poi.catalog()
    assert Map.has_key?(first, :id)
    assert Map.has_key?(first, :label)
    assert Map.has_key?(first, :icon)
    assert is_list(first.items)
    [first_item | _] = first.items
    assert Map.has_key?(first_item, :id)
    assert Map.has_key?(first_item, :selector)
    assert Map.has_key?(first_item, :pinned)
  end

  test "catalog/0 includes food.restaurant with correct selector" do
    food = Enum.find(Poi.catalog(), &(&1.id == "food"))
    restaurant = Enum.find(food.items, &(&1.id == "restaurant"))
    assert restaurant.selector == "amenity=restaurant"
    assert restaurant.pinned == true
  end

  test "nearby/1 with bbox + types issues Overpass bbox query, returns features with category", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/interpreter", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ ~s|node["amenity"="restaurant"]|
      assert body =~ "52.0,13.0,53.0,14.0"
      Plug.Conn.resp(conn, 200, ~s({"elements":[{"type":"node","id":1,"lat":52.5,"lon":13.4,"tags":{"amenity":"restaurant","name":"Brandenburger Bistro"}}]}))
    end)

    assert %Result{features: [feat], upstream_status: "ok"} =
             Poi.nearby(bbox: [13.0, 52.0, 14.0, 53.0], types: ["restaurant"])

    assert feat.id == "node/1"
    assert feat.name == "Brandenburger Bistro"
    assert feat.category == "restaurant"
    assert feat.tags["amenity"] == "restaurant"
  end

  test "nearby/1 returns error when types resolve to no selectors" do
    assert %Result{features: [], upstream_status: "error"} =
             Poi.nearby(bbox: [13.0, 52.0, 14.0, 53.0], types: ["does-not-exist"])
  end

  test "nearby/1 returns error when bbox missing" do
    assert %Result{features: [], upstream_status: "error"} = Poi.nearby(types: ["restaurant"])
  end
end
