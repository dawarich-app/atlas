defmodule AtlasWeb.Api.V1.CoverageControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Control.Service
  alias Atlas.Repo

  test "GET /api/v1/coverage returns readiness and regional coverage by capability", %{conn: conn} do
    for {name, status} <- [
          {"photon", :ready},
          {"valhalla", :ready},
          {"overpass", :stopped},
          {"otp", :ready}
        ] do
      Repo.insert!(%Service{name: name, profile: "x", status: status})
    end

    body = conn |> get(~p"/api/v1/coverage") |> json_response(200)
    capabilities = body["data"]["capabilities"]

    assert capabilities["geocoding"]["status"] == "up"
    assert capabilities["routing"]["available"]
    assert capabilities["map_matching"]["service"] == "valhalla"
    assert capabilities["map_matching"]["inherits"] == "routing"
    refute capabilities["pois"]["available"]
    assert is_list(capabilities["transit"]["transit_feeds"])
    assert body["meta"]["timestamp"]
  end

  test "the endpoint is included in the published OpenAPI spec", %{conn: conn} do
    spec = conn |> get(~p"/api/v1/openapi.json") |> json_response(200)

    assert get_in(spec, ["paths", "/api/v1/coverage", "get", "summary"]) =~ "regions"
  end
end
