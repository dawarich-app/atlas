defmodule AtlasWeb.MapContextTest do
  use ExUnit.Case, async: true
  alias AtlasWeb.MapContext

  test "restores confirmed names without geocoding them again and validates coordinates" do
    restored =
      MapContext.restore(%{
        "tab" => "route",
        "mode" => "transit",
        "query" => "cafes",
        "city" => "Berlin",
        "endpoints" => %{
          "from" => %{
            "query" => "Brandenburger Tor",
            "coords" => %{"lat" => 52.516, "lon" => 13.378}
          },
          "to" => %{"query" => "91, 181", "coords" => %{"lat" => 91, "lon" => 181}}
        },
        "viewport" => [13.3, 52.4, 13.5, 52.6]
      })

    assert restored.route_endpoints["from"].query == "Brandenburger Tor"
    assert restored.route_endpoints["from"].coords == %{lat: 52.516, lon: 13.378}
    assert restored.route_endpoints["to"].coords == nil
    assert restored.mode == "transit"
    assert restored.active_tab == "route"
    assert restored.search_city == "Berlin"
  end

  test "unknown modes and malformed bounds cannot become route options" do
    restored =
      MapContext.restore(%{
        "mode" => "unknown",
        "viewport" => [181, 90, 0, 0],
        "options" => %{"avoid_tolls" => "true", "other" => true}
      })

    assert restored.mode == "auto"
    assert restored.viewport == nil
    assert restored.route_options["avoid_tolls"] == false
    refute Map.has_key?(restored.route_options, "other")
  end

  test "malformed nested browser storage is ignored" do
    restored = MapContext.restore(%{"endpoints" => "invalid", "options" => [1]})
    assert restored.route_endpoints["from"].coords == nil
    assert restored.route_options["avoid_tolls"] == false
  end
end
