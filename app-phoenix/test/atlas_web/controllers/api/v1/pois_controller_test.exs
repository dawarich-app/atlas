defmodule AtlasWeb.Api.V1.PoisControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    System.put_env("OVERPASS_URL", "http://localhost:#{bypass.port}")
    System.put_env("PHOTON_URL", "http://localhost:#{bypass.port}")
    on_exit(fn ->
      System.delete_env("OVERPASS_URL")
      System.delete_env("PHOTON_URL")
    end)
    {:ok, bypass: bypass}
  end

  test "GET /api/v1/pois returns features with bbox + types", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/interpreter", fn c ->
      Plug.Conn.resp(c, 200, ~s({"elements":[{"type":"node","id":1,"lat":52.5,"lon":13.4,"tags":{"amenity":"cafe","name":"Café Berlin"}}]}))
    end)

    resp =
      conn
      |> get(~p"/api/v1/pois?bbox=52.0,13.0,53.0,14.0&types=cafe")
      |> json_response(200)

    assert [%{"name" => "Café Berlin", "category" => "cafe"}] = resp["data"]["features"]
    assert resp["meta"]["upstream"] == "ok"
    assert resp["meta"]["count"] == 1
    assert resp["meta"]["types"] == ["cafe"]
  end

  test "GET /api/v1/pois returns 400 without bbox", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/pois") |> json_response(400)
    assert resp["error"]["code"] == "MISSING_PARAM"
  end

  test "GET /api/v1/pois returns 422 VALIDATION_ERROR when bbox is malformed", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/pois?bbox=garbage") |> json_response(422)
    assert resp["error"]["code"] == "VALIDATION_ERROR"
    assert resp["error"]["message"] =~ "bbox"
  end

  test "GET /api/v1/pois with q= dispatches to Photon search-within-categories", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/api", fn c ->
      q = URI.decode_query(c.query_string)
      assert q["q"] == "bistro"
      # Photon receives w,s,e,n; internal s,w,n,e = 52.0,13.0,53.0,14.0 → 13.0,52.0,14.0,53.0
      assert q["bbox"] == "13.0,52.0,14.0,53.0"
      Plug.Conn.resp(c, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"osm_type":"N","osm_id":1,"name":"Bistro Berlin","osm_key":"amenity","osm_value":"restaurant"}}]}))
    end)

    resp =
      conn
      |> get(~p"/api/v1/pois?bbox=52.0,13.0,53.0,14.0&types=restaurant&q=bistro")
      |> json_response(200)

    assert [%{"name" => "Bistro Berlin", "category" => "restaurant"}] = resp["data"]["features"]
    assert resp["meta"]["q"] == "bistro"
  end

  test "GET /api/v1/pois with empty types defaults to first 2 pinned catalog items", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/interpreter", fn c ->
      Plug.Conn.resp(c, 200, ~s({"elements":[]}))
    end)

    resp = conn |> get(~p"/api/v1/pois?bbox=52.0,13.0,53.0,14.0") |> json_response(200)

    types = resp["meta"]["types"]
    assert is_list(types)
    assert length(types) > 0
    assert length(types) <= 2

    pinned_ids = Atlas.Maps.Poi.Catalog.pinned() |> Enum.take(2) |> Enum.map(& &1.id)
    assert types == pinned_ids
  end

  test "GET /api/v1/pois returns 422 when all types are unknown", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/pois?bbox=52.0,13.0,53.0,14.0&types=does-not-exist,also-bogus") |> json_response(422)
    assert resp["error"]["code"] == "VALIDATION_ERROR"
    assert resp["error"]["message"] =~ "no recognised types"
  end

  test "GET /api/v1/pois/categories returns nested sections", %{conn: conn} do
    resp = conn |> get(~p"/api/v1/pois/categories") |> json_response(200)
    sections = resp["data"]["sections"]
    assert is_list(sections)
    food = Enum.find(sections, &(&1["id"] == "food"))
    assert food["label"] == "Food & Drink"
    restaurant = Enum.find(food["items"], &(&1["id"] == "restaurant"))
    assert restaurant["pinned"] == true
  end
end
