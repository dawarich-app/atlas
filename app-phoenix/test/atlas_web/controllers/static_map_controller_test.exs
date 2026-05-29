defmodule AtlasWeb.StaticMapControllerTest do
  use AtlasWeb.ConnCase, async: false

  alias Atlas.Settings

  test "GET /static_map renders the static layout with defaults", %{conn: conn} do
    conn = get(conn, ~p"/static_map")
    body = html_response(conn, 200)

    assert body =~ ~s(id="static-map")
    # Defaults: width=800, height=600, lat=51.1657, lon=10.4515, zoom=5
    assert body =~ "800"
    assert body =~ "600"
    assert body =~ "51.1657"
    assert body =~ "Dawarich Atlas"
  end

  test "GET /static_map respects query params and clamps width/height", %{conn: conn} do
    conn =
      get(conn, ~p"/static_map", %{
        "lat" => "52.5",
        "lon" => "13.4",
        "zoom" => "12",
        "width" => "100000",
        "height" => "10",
        "title" => "Berlin trip",
        "subtitle" => "Day 1"
      })

    body = html_response(conn, 200)

    assert body =~ "52.5"
    assert body =~ "13.4"
    # Width clamped to 4096
    assert body =~ "4096"
    # Height clamped to 64
    assert body =~ "height:64px"
    assert body =~ "Berlin trip"
    assert body =~ "Day 1"
  end

  test "GET /static_map prefers query theme over settings", %{conn: conn} do
    Settings.set("tiles_theme", "atlas-light")
    conn = get(conn, ~p"/static_map", %{"theme" => "atlas-dark"})
    body = html_response(conn, 200)

    assert body =~ ~s(data-theme="atlas-dark")
  end

  test "GET /static_map reads tiles_url from settings", %{conn: conn} do
    Settings.set("tiles_url", "https://tiles.example/style.json")

    conn = get(conn, ~p"/static_map")
    body = html_response(conn, 200)

    assert body =~ "https://tiles.example/style.json"
  end

  test "GET /static_map with route polyline emits non-empty data-route-geojson", %{conn: conn} do
    # Google's official sample at precision 6 — we don't care about exact coords,
    # only that the server decoded the polyline and emitted GeoJSON in the data attribute.
    encoded = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"

    conn = get(conn, ~p"/static_map", %{"route" => encoded})
    body = html_response(conn, 200)

    assert body =~ "data-route-geojson="
    assert body =~ "FeatureCollection"
    assert body =~ "LineString"
    refute body =~ ~s(data-route-geojson="")
    refute body =~ ~s(data-route-geojson="null")
  end

  test "GET /static_map without route emits empty data-route-geojson", %{conn: conn} do
    conn = get(conn, ~p"/static_map")
    body = html_response(conn, 200)

    assert body =~ ~s(data-route-geojson="")
  end

  test "GET /static_map markup includes the ready-signal JS hook", %{conn: conn} do
    conn = get(conn, ~p"/static_map")
    body = html_response(conn, 200)

    assert body =~ "__atlasStaticMapReady"
    assert body =~ "atlas:static-map-ready"
  end

  test "GET /static_map handles invalid query params via fallbacks", %{conn: conn} do
    conn =
      get(conn, ~p"/static_map", %{
        "lat" => "garbage",
        "lon" => "more garbage",
        "zoom" => "",
        "width" => "abc"
      })

    body = html_response(conn, 200)

    # Falls back to default lat 51.1657
    assert body =~ "51.1657"
    # Falls back to default width 800
    assert body =~ "800"
  end
end
