defmodule Atlas.Control.HealthTest do
  use ExUnit.Case, async: true
  alias Atlas.Control.Health

  test "summarize maps each capability to its primary service's normalized status" do
    statuses = %{
      "photon" => "ready",
      "valhalla" => "stopped",
      "overpass" => "ready",
      "otp" => "starting"
    }

    assert Health.summarize(statuses) == %{
             status: "degraded",
             capabilities: %{
               "geocoding" => "up",
               "routing" => "down",
               "pois" => "up",
               "transit" => "starting"
             }
           }
  end

  test "summarize reports overall up when all primary services are ready" do
    statuses = %{
      "photon" => "ready",
      "valhalla" => "ready",
      "overpass" => "ready",
      "otp" => "ready"
    }

    assert Health.summarize(statuses).status == "up"
  end

  test "summarize reports overall down when all primary services are down" do
    statuses = %{
      "photon" => "error",
      "valhalla" => nil,
      "overpass" => "stopped",
      "otp" => "error"
    }

    assert Health.summarize(statuses).status == "down"
  end

  test "a missing service status normalizes to down" do
    assert Health.summarize(%{}).capabilities["geocoding"] == "down"
  end

  test "summarize handles atom statuses from the Ecto.Enum column" do
    assert Health.summarize(%{"photon" => :ready}).capabilities["geocoding"] == "up"
  end

  test "an :unknown service status normalizes to down" do
    assert Health.summarize(%{"valhalla" => :unknown}).capabilities["routing"] == "down"
  end
end
