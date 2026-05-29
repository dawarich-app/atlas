defmodule AtlasWeb.Api.V1.PoisControllerTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    bypass = Bypass.open()
    System.put_env("OVERPASS_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("OVERPASS_URL") end)
    {:ok, bypass: bypass}
  end

  test "GET /api/v1/pois returns features with bbox + types", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/interpreter", fn c ->
      Plug.Conn.resp(c, 200, ~s({"elements":[{"type":"node","id":1,"lat":52.5,"lon":13.4,"tags":{"amenity":"cafe","name":"Café Berlin"}}]}))
    end)

    resp =
      conn
      |> get(~p"/api/v1/pois?bbox=13.0,52.0,14.0,53.0&types=cafe")
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
