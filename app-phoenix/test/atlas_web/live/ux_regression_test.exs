defmodule AtlasWeb.UxRegressionTest do
  use AtlasWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "recovery opens embedded Services and Back returns to Directions", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    render_click(element(view, "button[aria-label=Directions]"))
    render_hook(view, "open_services", %{})
    assert has_element?(view, "button[phx-value-tab=services][aria-pressed=true]")
    refute render(view) =~ "href=\"/admin/services\""
    render_click(element(view, "button[phx-click=back_to_map]"))
    assert has_element?(view, "button[aria-label=Directions].btn-primary")
    assert_push_event(view, "map:active_tab", %{tab: "route"})
  end

  test "walking hides car options and preserves options disclosure on mode change", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    render_hook(view, "select_tab", %{"tab" => "route"})
    render_hook(view, "toggle_route_options", %{})
    assert has_element?(view, "input[phx-value-option=avoid_highways]")
    render_hook(view, "set_mode", %{"mode" => "pedestrian"})
    refute has_element?(view, "input[phx-value-option=avoid_highways]")
    assert has_element?(view, "input[phx-value-option=avoid_ferries]")
    render_hook(view, "set_mode", %{"mode" => "transit"})
    assert has_element?(view, "#route-departure")
    refute has_element?(view, "input[phx-value-option=avoid_ferries]")
  end

  test "browser draft restores endpoints and active tab without changing service settings", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/")

    render_hook(view, "restore_map_context", %{
      "tab" => "route",
      "endpoints" => %{
        "from" => %{"query" => "Gate", "coords" => %{"lat" => 52.516, "lon" => 13.378}}
      }
    })

    assert has_element?(view, ~s(#route-from[value="Gate"]))
    assert has_element?(view, "button[aria-label=Directions].btn-primary")

    assert_push_event(view, "map:set_route_endpoints", %{
      points: [%{field: "from", label: "Gate"}]
    })
  end

  test "explicit step survives transport-source roundtrip after failed installation", %{
    conn: conn
  } do
    Atlas.Settings.set(
      "setup_job",
      Jason.encode!(%{"status" => "failed", "error" => "Download failed", "services" => []})
    )

    {:ok, view, _} = live(conn, "/setup?step=3")
    assert has_element?(view, "h2", "Ready to install")
    {:ok, sources, _} = live(conn, "/transport-data?from=setup&step=3")
    assert has_element?(sources, ~s(a[href="/setup?step=3"]), "Back to setup")
  end

  test "refresh can restore a matching search draft but shared searches win", %{conn: conn} do
    {:ok, view, _} = live(conn, "/?q=Berlin")
    render_hook(view, "restore_map_context", %{"query" => "Hamburg", "tab" => "route"})
    assert has_element?(view, ~s(#search-input[value="Berlin"]))
    refute has_element?(view, "button[aria-label=Directions].btn-primary")
    render_hook(view, "restore_map_context", %{"query" => "Berlin", "tab" => "route"})
    assert has_element?(view, "button[aria-label=Directions].btn-primary")
  end
end
