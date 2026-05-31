defmodule AtlasWeb.MapLiveTest do
  use AtlasWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    bypass = Bypass.open()

    Enum.each(
      ~w[PHOTON_URL PLACEHOLDER_URL LIBPOSTAL_URL VALHALLA_URL],
      &System.put_env(&1, "http://localhost:#{bypass.port}")
    )

    on_exit(fn ->
      Enum.each(
        ~w[PHOTON_URL PLACEHOLDER_URL LIBPOSTAL_URL VALHALLA_URL],
        &System.delete_env/1
      )
    end)

    {:ok, bypass: bypass}
  end

  test "GET / renders map and sidebar cards", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Search"
    assert html =~ "Directions"
    assert html =~ "Places"
    assert html =~ "Settings"
    assert html =~ ~s(id="map")
    assert html =~ ~s(phx-hook="Map")
  end

  test "search submit populates results", %{conn: conn, bypass: bypass} do
    Bypass.expect(bypass, fn c ->
      case c.request_path do
        "/parser" ->
          Plug.Conn.resp(c, 200, "[]")

        "/api" ->
          Plug.Conn.resp(
            c,
            200,
            ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"Berlin","city":"Berlin","country":"Germany","osm_id":1,"osm_type":"R","osm_key":"place","osm_value":"city"}}]})
          )

        "/parser/search" ->
          Plug.Conn.resp(c, 200, "[]")

        _ ->
          Plug.Conn.resp(c, 200, "[]")
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("form[phx-submit=search]", %{"q" => "berlin"})
      |> render_submit()

    assert html =~ "Berlin"
  end

  test "status_changed handler does not crash the LiveView", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    send(view.pid, :status_changed)

    # Re-render proves the process is still alive and the message was processed.
    assert render(view) =~ "Search"
  end

  test "route event pushes map:draw_route with decoded LineString features", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect(bypass, fn c ->
      case c.request_path do
        "/route" ->
          body =
            ~s({"trip":{"summary":{"length":1.0,"time":60},"legs":[{"shape":"_p~iF~ps|U_ulLnnqC_mqNvxq`@","summary":{"length":1.0,"time":60}}]}})

          Plug.Conn.resp(c, 200, body)

        _ ->
          Plug.Conn.resp(c, 200, "{}")
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "route", %{"from" => "38.5,-120.2", "to" => "43.252,-126.453"})

    assert_push_event(view, "map:draw_route", %{geojson: geojson})

    assert %{type: "FeatureCollection", features: features} = geojson
    assert length(features) >= 1

    Enum.each(features, fn feature ->
      assert %{type: "Feature", geometry: %{type: "LineString", coordinates: coords}} = feature
      assert is_list(coords)
      assert length(coords) >= 2
    end)
  end
end
