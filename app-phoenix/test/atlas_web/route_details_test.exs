defmodule AtlasWeb.RouteDetailsTest do
  use ExUnit.Case, async: true
  alias AtlasWeb.RouteDetails

  test "prefers the quickest transit connection over a walking-only result" do
    walk = %{duration: 100, legs: [%{mode: "WALK"}]}
    bus = %{duration: 900, legs: [%{mode: "WALK"}, %{mode: "BUS", route_name: "166"}]}
    train = %{duration: 600, legs: [%{mode: "RAIL", route_name: "S41"}]}
    result = RouteDetails.prepare(%{itineraries: [walk, bus, train]}, "transit")
    assert result.itineraries == [train, bus, walk]
    assert RouteDetails.legs(result) == train.legs
    assert RouteDetails.duration(result) == "10 min"
  end

  test "a walking-only fallback is not classified as transit" do
    result =
      RouteDetails.prepare(%{itineraries: [%{duration: 60, legs: [%{mode: "WALK"}]}]}, "transit")

    refute RouteDetails.transit?(RouteDetails.itinerary(result))
  end

  test "Valhalla walking legs carry a mode for the dashed map layer" do
    result = RouteDetails.prepare(%{legs: [%{"shape" => "abc"}]}, "pedestrian")
    assert [%{mode: "WALK"}] = RouteDetails.legs(result)
  end
end
