defmodule AtlasWeb.ApiSpecTest do
  use AtlasWeb.ConnCase, async: false

  test "GET /api/v1/openapi.json returns a valid OpenAPI document", %{conn: conn} do
    spec = conn |> get(~p"/api/v1/openapi.json") |> json_response(200)

    assert spec["openapi"]
    assert spec["info"]["title"] == "Dawarich Atlas API"
    assert is_map(spec["paths"]["/api/v1/search"])
    assert is_map(spec["paths"]["/api/v1/reverse"])
    assert is_map(spec["paths"]["/api/v1/route"])
    assert is_map(spec["paths"]["/api/v1/transit"])
    assert is_map(spec["paths"]["/api/v1/whats-here"])
    assert is_map(spec["paths"]["/api/v1/pois"])
    assert is_map(spec["paths"]["/api/v1/pois/categories"])
    assert is_map(spec["paths"]["/api/v1/geocode"])
  end
end
