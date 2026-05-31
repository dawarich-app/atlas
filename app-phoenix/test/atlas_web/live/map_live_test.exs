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

  test "point_picked writes value into the From input", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "point_picked", %{"field" => "from", "lat" => 52.5, "lon" => 13.4})

    html = render(view)
    assert html =~ ~s(value="52.500000,13.400000")
  end

  test "point_picked writes value into the To input", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "point_picked", %{"field" => "to", "lat" => 51.0, "lon" => 10.0})

    html = render(view)
    assert html =~ ~s(value="51.000000,10.000000")
  end

  test "pick_point pushes map:enter_picker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "pick_point", %{"field" => "from"})

    # The push_event lands in the view's assigns/push log; assert_push_event helps.
    assert_push_event(view, "map:enter_picker", %{field: "from"})
  end

  test "toggle_region toggles RegionSelection rows", %{conn: conn} do
    import Ecto.Query
    alias Atlas.Control.RegionSelection
    alias Atlas.Repo

    Repo.delete_all(RegionSelection)

    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "toggle_region", %{"name" => "germany"})
    rows = Repo.all(from r in RegionSelection, where: r.region_name == ^"germany")
    assert [%RegionSelection{active: true, region_name: "germany"}] = rows

    render_hook(view, "toggle_region", %{"name" => "germany"})
    assert Repo.all(from r in RegionSelection, where: r.region_name == ^"germany") == []
  end

  test "toggle_service does not crash even if DockerCompose is unavailable", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Even if no docker is available, the LiveView must stay up.
    render_hook(view, "toggle_service", %{"name" => "photon"})

    assert render(view) =~ "Settings"
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
