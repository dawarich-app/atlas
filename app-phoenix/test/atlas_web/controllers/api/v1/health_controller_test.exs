defmodule AtlasWeb.Api.V1.HealthControllerTest do
  use AtlasWeb.ConnCase, async: true
  alias Atlas.Repo
  alias Atlas.Control.Service

  test "GET /api/v1/health returns per-capability statuses in the data envelope", %{conn: conn} do
    for {name, status} <- [
          {"photon", :ready},
          {"valhalla", :stopped},
          {"overpass", :ready},
          {"otp", :ready}
        ] do
      Repo.insert!(%Service{name: name, profile: "x", status: status})
    end

    body = conn |> get(~p"/api/v1/health") |> json_response(200)

    assert body["data"]["status"] == "degraded"
    assert body["data"]["capabilities"]["geocoding"] == "up"
    assert body["data"]["capabilities"]["routing"] == "down"
    assert body["meta"]["timestamp"]
  end
end
