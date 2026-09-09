defmodule AtlasWeb.RouteDetailsTest do
  use ExUnit.Case, async: true
  alias AtlasWeb.RouteDetails

  test "itinerary times support both MOTIS ISO and OTP milliseconds" do
    assert RouteDetails.timestamp("2026-09-09T08:00:00Z") == "2026-09-09T08:00:00Z"
    {:ok, dt, _} = DateTime.from_iso8601("2026-09-09T08:00:00Z")
    assert RouteDetails.timestamp(DateTime.to_unix(dt, :millisecond)) =~ "2026-09-09T08:00:00"
    assert RouteDetails.timestamp(nil) == nil
    assert RouteDetails.place_name(%{name: "END"}, "Alexanderplatz") == "Alexanderplatz"
    assert RouteDetails.label("REGIONAL_RAIL") == "Regional rail"

    assert RouteDetails.wait_before(
             [%{end_time: "2026-09-09T08:00:00Z"}, %{start_time: "2026-09-09T08:04:00Z"}],
             1
           ) == 240

    assert RouteDetails.time_status(%{realtime: false}) == "Scheduled"
  end

  test "prefers the quickest transit connection over a walking-only result" do
    walk = %{duration: 100, legs: [%{mode: "WALK"}]}
    bus = %{duration: 900, legs: [%{mode: "WALK"}, %{mode: "BUS", route_name: "166"}]}
    train = %{duration: 600, legs: [%{mode: "RAIL", route_name: "S41"}]}
    result = RouteDetails.prepare(%{itineraries: [walk, bus, train]}, "transit")
    assert result.itineraries == [train, bus, walk]

    assert Enum.map(RouteDetails.legs(result), &Map.drop(&1, [:color, :route_label])) ==
             train.legs

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

  test "map and itinerary share distinct transit colours, labels and neutral walking" do
    legs = [
      %{mode: "WALK"},
      %{mode: "RAIL", route_name: "S85", shape: "_p~iF~ps|U_ulLnnqC_mqNvxq`@"},
      %{mode: "WALK"},
      %{mode: "RAIL", route_name: "S7", shape: "_p~iF~ps|U_ulLnnqC_mqNvxq`@"},
      %{mode: "RAIL", route_name: "S85"}
    ]

    result = RouteDetails.prepare(%{itineraries: [%{duration: 600, legs: legs}]}, "transit")
    [walk, s85, _, s7, repeated] = styled = RouteDetails.legs(result)
    assert styled == RouteDetails.itinerary(result).legs
    assert walk.route_label == nil
    assert s85.route_label == "S85"
    assert s7.route_label == "S7"
    assert s85.color != s7.color
    assert repeated.color == s85.color
    assert walk.color not in [s85.color, s7.color]
    assert %{features: [first, second]} = Atlas.Geometry.Coord.legs_to_geojson(styled)
    assert first.properties.color == s85.color
    assert second.properties.route_label == "S7"
  end
end
