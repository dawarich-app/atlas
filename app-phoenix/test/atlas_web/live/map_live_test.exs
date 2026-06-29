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

  test "toggle_service stages an intent instead of starting the service", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Staging must not crash the LiveView even when docker is unavailable.
    render_hook(view, "toggle_service", %{"name" => "photon"})

    html = render(view)
    assert html =~ "Settings"
    # A pending-changes summary now lists photon among the staged enables.
    assert html =~ "Pending changes"
    assert html =~ "photon"
  end

  test "applying a staged service clears the pending summary", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "toggle_service", %{"name" => "photon"})
    assert render(view) =~ "Pending changes"

    render_hook(view, "apply_selection", %{})

    # Safe.call swallows the unavailable ServiceState/RegionApplier; pending clears.
    refute render(view) =~ "Pending changes"
  end

  test "toggling a staged service back to its current state removes it from pending",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "toggle_service", %{"name" => "photon"})
    assert render(view) =~ "Pending changes"

    render_hook(view, "toggle_service", %{"name" => "photon"})
    refute render(view) =~ "Pending changes"
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

  describe "service logs modal" do
    test "opens full-page, streams lines, and closes from the root LiveView", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=settings")

      view
      |> element("button[phx-click=settings_tab][phx-value-tab=services]")
      |> render_click()

      view
      |> element(~s(button[phx-click=open_logs][phx-value-name=photon]))
      |> render_click()

      html = render(view)
      # Full-page overlay (fixed to the viewport, not absolute inside the panel).
      assert html =~ ~s(data-role="logs-modal")
      assert html =~ "fixed inset-0"
      assert html =~ "Waiting for log output…" or html =~ "Could not start the log stream"

      send(view.pid, {:log_line, "photon booted"})
      assert render(view) =~ "photon booted"

      view |> element("button[phx-click=close_logs]") |> render_click()
      refute render(view) =~ ~s(data-role="logs-modal")
    end

    test "modal panel does not swallow clicks with stopPropagation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=settings")

      view
      |> element("button[phx-click=settings_tab][phx-value-tab=services]")
      |> render_click()

      view
      |> element(~s(button[phx-click=open_logs][phx-value-name=photon]))
      |> render_click()

      refute render(view) =~ "stopPropagation"
    end
  end

  describe "apply progress" do
    test "apply lifecycle broadcasts render the progress card, then the error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      job_id = Ecto.UUID.generate()

      send(view.pid, {:apply_start, %{job_id: job_id, regions: ["berlin"]}})

      send(
        view.pid,
        {:apply_progress,
         %{job_id: job_id, phase: :downloading, region: "berlin", progress: 0.4}}
      )

      html = render(view)
      assert html =~ "apply-card"
      assert html =~ "Applying berlin"
      assert html =~ "40%"

      send(
        view.pid,
        {:apply_error, %{job_id: job_id, phase: :downloading, reason: "HTTP 503"}}
      )

      html = render(view)
      assert html =~ "Region apply failed"
      assert html =~ "HTTP 503"
    end

    test "apply_done clears the progress card", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      job_id = Ecto.UUID.generate()
      send(view.pid, {:apply_start, %{job_id: job_id, regions: ["berlin"]}})
      assert render(view) =~ "apply-card"

      send(view.pid, {:apply_done, %{job_id: job_id, regions: ["berlin"]}})
      refute render(view) =~ "apply-card"
    end
  end
end
