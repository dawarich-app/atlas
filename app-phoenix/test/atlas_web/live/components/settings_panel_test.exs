defmodule AtlasWeb.SettingsPanelTest do
  use AtlasWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Atlas.Control.RegionSelection
  alias Atlas.Repo

  defp open_settings(conn) do
    {:ok, view, _html} = live(conn, ~p"/?tab=settings")
    {:ok, view, render(view)}
  end

  test "settings panel surfaces the headline sections from M5+ parity work",
       %{conn: conn} do
    {:ok, _view, html} = open_settings(conn)

    # The control-plane header + the four functional groupings PR #10
    # collapsed onto a single tab: Region, Basemap, Services, Apply.
    assert html =~ "Back to map"
    assert html =~ "Settings"
    assert html =~ "Region"
    assert html =~ "Basemap"
    assert html =~ "Services"
    assert html =~ "Apply changes"
  end

  test "regions section renders continent roots as selectable tree nodes",
       %{conn: conn} do
    {:ok, _view, html} = open_settings(conn)

    # The Region body is now a collapsible hierarchical tree. Continent roots
    # (parent == nil) render at the top level with a stable data-node hook and
    # a per-node size hint; selection stays a checkbox-driven toggle.
    assert html =~ ~s(data-node="gf:asia")
    assert html =~ "Asia"
    assert html =~ "toggle_region"
  end

  test "region search auto-expands matches and their ancestors in the tree",
       %{conn: conn} do
    {:ok, view, _html} = open_settings(conn)

    html =
      view
      |> element("form[phx-change=region_search]")
      |> render_change(%{q: "anhui"})

    # The matched leaf and every ancestor up to the continent root render,
    # auto-expanded (Asia ▸ China ▸ Anhui). Unrelated continent branches
    # (Antarctica) are hidden.
    assert html =~ ~s(data-node="gf:anhui")
    assert html =~ ~s(data-node="gf:china")
    assert html =~ ~s(data-node="gf:asia")
    refute html =~ ~s(data-node="gf:antarctica")
  end

  test "region search with no matches shows an empty-state message",
       %{conn: conn} do
    {:ok, view, _html} = open_settings(conn)

    html =
      view
      |> element("form[phx-change=region_search]")
      |> render_change(%{q: "zzzznomatch"})

    assert html =~ "No regions match"
    refute html =~ "Germany"
  end

  test "regions section reflects active selections from the DB",
       %{conn: conn} do
    Repo.delete_all(RegionSelection)
    Repo.insert!(%RegionSelection{region_name: "berlin", active: true, position: 0})

    {:ok, _view, html} = open_settings(conn)

    # Stats strip shows the active region label (derived from the region name).
    assert html =~ "Berlin"
  end

  test "basemap presets render with their labels", %{conn: conn} do
    {:ok, _view, html} = open_settings(conn)

    # PR #10 ports the Rails BasemapPresets list (openfreemap variants,
    # protomaps planet, …). Verify a couple of the well-known entries
    # appear as preset cards.
    assert html =~ "OpenFreeMap Liberty"
    assert html =~ "OpenFreeMap Positron"
  end

  test "services section renders the seven known sidecar names",
       %{conn: conn} do
    {:ok, _view, html} = open_settings(conn)

    # Each sidecar from Seeder.known_services/0 gets its own row in the
    # Services profile groups (Geocoding / Routing / POIs / Transit / …).
    for name <- ~w(libpostal photon placeholder valhalla overpass otp whosonfirst) do
      assert html =~ name, "expected #{name} in services list"
    end
  end

  test "ready stat numerator never exceeds the known-service total" do
    known = Atlas.Control.Seeder.known_services()

    # Every known service ready, plus an extra non-known :ready snapshot that
    # must NOT inflate the numerator beyond the denominator.
    status =
      known
      |> Map.new(fn %{name: name} -> {name, %{status: :ready}} end)
      |> Map.put("not-a-known-service", %{status: :ready})

    html =
      render_component(AtlasWeb.SettingsPanel,
        id: "settings-panel",
        tiles_url: "",
        theme: "forest-patina",
        service_status: status,
        pending_services: %{},
        tiles_download: nil
      )

    total = length(known)
    assert html =~ "#{total} running"
    refute html =~ "#{total + 1} running"
  end

  test "region tab is the default active sub-tab", %{conn: conn} do
    {:ok, view, _html} = open_settings(conn)

    assert has_element?(view, "#settings-tab-region.block")
    assert has_element?(view, "#settings-tab-basemap.hidden")
    assert has_element?(view, "#settings-tab-services.hidden")
  end

  test "clicking the Basemap sub-tab reveals basemap and hides region",
       %{conn: conn} do
    {:ok, view, _html} = open_settings(conn)

    view
    |> element("button[phx-click=settings_tab][phx-value-tab=basemap]")
    |> render_click()

    assert has_element?(view, "#settings-tab-basemap.block")
    assert has_element?(view, "#settings-tab-region.hidden")
  end

  test "service category accordion collapses and expands", %{conn: conn} do
    {:ok, view, _html} = open_settings(conn)

    view
    |> element("button[phx-click=settings_tab][phx-value-tab=services]")
    |> render_click()

    # Categories open by default — collapsing geocoding hides the photon row.
    collapsed =
      view
      |> element("button[phx-click=toggle_cat][phx-value-cat=geocoding]")
      |> render_click()

    refute collapsed =~ ~s(phx-value-name="photon")

    expanded =
      view
      |> element("button[phx-click=toggle_cat][phx-value-cat=geocoding]")
      |> render_click()

    assert expanded =~ ~s(phx-value-name="photon")
  end

  test "toggling a service stages it via the parent toggle_service handler",
       %{conn: conn} do
    {:ok, view, _html} = open_settings(conn)

    view
    |> element("button[phx-click=settings_tab][phx-value-tab=services]")
    |> render_click()

    # The checkbox carries the parent-handled toggle_service event; clicking it
    # stages the intent (handled in MapLive) rather than starting the container.
    html =
      view
      |> element(~s(input[phx-click=toggle_service][phx-value-name=photon]))
      |> render_click()

    assert html =~ "photon"
    # Staging surfaces the pending-changes summary.
    assert html =~ "Pending changes"
  end

  test "service-only changes do not show an invented installation estimate",
       %{conn: conn} do
    {:ok, view, _html} = open_settings(conn)

    view
    |> element("button[phx-click=settings_tab][phx-value-tab=services]")
    |> render_click()

    html =
      view
      |> element(~s(input[phx-click=toggle_service][phx-value-name=photon]))
      |> render_click()

    assert html =~ "Pending changes"
    refute html =~ "first boot"
    assert html =~ "Discard changes"
  end

  test "opening logs surfaces the logs modal for that service",
       %{conn: conn} do
    {:ok, view, _html} = open_settings(conn)

    view
    |> element("button[phx-click=settings_tab][phx-value-tab=services]")
    |> render_click()

    view
    |> element(~s(button[phx-click=open_logs][phx-value-name=photon]))
    |> render_click()

    # The open event round-trips through MapLive (subscribe + tailer start);
    # the streaming viewer shows its waiting state until lines arrive.
    html = render(view)
    assert html =~ "Waiting for log output…" or html =~ "Could not start the log stream"
    assert has_element?(view, "button[phx-click=close_logs]")

    # A line broadcast on the service's log topic appears in the modal.
    send(view.pid, {:log_line, "photon booted in 3s"})
    assert render(view) =~ "photon booted in 3s"

    # EOF is announced instead of freezing silently.
    send(view.pid, {:log_eof, 0})
    assert render(view) =~ "log stream ended (exit 0)"
  end

  test "clicking a region row persists the selection and re-renders the panel",
       %{conn: conn} do
    Repo.delete_all(RegionSelection)
    {:ok, view, _html} = live(conn, ~p"/?tab=settings")

    view
    |> element(~s([data-node="gf:asia"] input[phx-click="toggle_region"]))
    |> render_click()

    # toggle_region is parent-handled (MapLive); the send_update/2 it issues makes
    # the panel re-read + re-render the selection rather than silently no-op.
    assert Repo.get_by(RegionSelection, region_name: "gf:asia", active: true)
    assert render(view) =~ ~s(data-node="gf:asia")
  end

  test "preflight failures render a degraded banner with the remedy", %{conn: conn} do
    :persistent_term.put(
      {Atlas.Control.Preflight, :results},
      [
        %{
          check: :socket,
          status: :error,
          detail: "permission denied on /var/run/docker.sock",
          remedy: "Set DOCKER_GID to the docker socket's group."
        }
      ]
    )

    on_exit(fn -> Atlas.Control.Preflight.clear() end)

    {:ok, _view, _html} = open_settings(conn)
    {:ok, view, _} = live(conn, ~p"/?tab=settings")

    html = render(view)
    assert html =~ "Control plane degraded"
    assert html =~ "DOCKER_GID"
  end

  test "selected regions render as removable chips with clear-all", %{conn: conn} do
    Repo.delete_all(RegionSelection)
    Repo.insert!(%RegionSelection{region_name: "gf:asia", active: true, position: 0})
    Repo.insert!(%RegionSelection{region_name: "gf:europe", active: true, position: 1})

    {:ok, view, _html} = live(conn, ~p"/?tab=settings")

    html = render(view)
    assert html =~ "Selected regions (2)"
    assert html =~ ~s(data-selected-chip="gf:asia")
    assert html =~ ~s(data-selected-chip="gf:europe")

    # Removing one chip deselects just that region.
    view |> element(~s(button[data-selected-chip="gf:asia"])) |> render_click()
    refute Repo.get_by(RegionSelection, region_name: "gf:asia")
    assert Repo.get_by(RegionSelection, region_name: "gf:europe", active: true)

    # Clear-all empties the tray.
    view |> element(~s(button[phx-click="clear_regions"])) |> render_click()
    assert Atlas.Control.RegionSelection.active_names() == []
    refute render(view) =~ "Selected regions"
  end

  test "apply button stays disabled when the selection matches the last apply", %{conn: conn} do
    Repo.delete_all(RegionSelection)
    Repo.insert!(%RegionSelection{region_name: "gf:asia", active: true, position: 0})
    Atlas.Control.RegionSelection.mark_applied!()

    {:ok, view, _html} = live(conn, ~p"/?tab=settings")

    assert render(view) =~ "Apply changes"
    assert has_element?(view, "button[phx-click=apply_selection][disabled]")

    # A new selection re-arms the button.
    view
    |> element(~s([data-node="gf:africa"] input[phx-click="toggle_region"]))
    |> render_click()

    assert render(view) =~ "Apply changes (1)"
    refute has_element?(view, "button[phx-click=apply_selection][disabled]")
  end

  test "the region tree expand chevron reveals children without selecting the node",
       %{conn: conn} do
    Repo.delete_all(RegionSelection)
    {:ok, view, _html} = live(conn, ~p"/?tab=settings")

    # A country under Asia is not rendered until the continent is expanded.
    refute render(view) =~ ~s(data-node="gf:china")

    html =
      view
      |> element(~s([data-node="gf:asia"] button[phx-click="toggle_node"]))
      |> render_click()

    assert html =~ ~s(data-node="gf:china")
    # Expanding must not also select the continent.
    refute Repo.get_by(RegionSelection, region_name: "gf:asia", active: true)
  end

  test "the apply card names the file, its source and the step", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    timeline =
      ["Germany"]
      |> Atlas.Control.ApplyTimeline.start([], DateTime.utc_now())
      |> Atlas.Control.ApplyTimeline.apply_event(
        {:apply_progress,
         %{
           phase: :downloading,
           region: "germany",
           item: %{
             label: "germany-latest.osm.pbf",
             source: "https://download.geofabrik.de/europe/germany-latest.osm.pbf",
             current: 1024,
             total: 4096
           }
         }},
        DateTime.utc_now()
      )

    send(view.pid, {:timeline, timeline})

    html = render(view)

    assert html =~ "germany-latest.osm.pbf"
    assert html =~ "download.geofabrik.de"
    assert html =~ "step 1 of 4"
  end

  test "an indeterminate measure renders bytes, never a percentage", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    timeline =
      ["Germany"]
      |> Atlas.Control.ApplyTimeline.start([], DateTime.utc_now())
      |> Atlas.Control.ApplyTimeline.apply_event(
        {:apply_progress,
         %{
           phase: :downloading,
           region: "germany",
           item: %{label: "a.pbf", source: "http://x/a.pbf", current: 2048, total: nil}
         }},
        DateTime.utc_now()
      )

    send(view.pid, {:timeline, timeline})

    timeline_html =
      view
      |> element(~s([data-role="apply-timeline"]))
      |> render()

    assert timeline_html =~ "2.0 KB"
    refute timeline_html =~ "%"
  end

  test "discard restores applied regions and clears staged services", %{conn: conn} do
    RegionSelection.clear()
    RegionSelection.toggle("gf:asia")
    RegionSelection.mark_applied!()
    RegionSelection.clear()

    {:ok, view, _} = open_settings(conn)
    view |> element("button[phx-click=select_tab][phx-value-tab=settings]") |> render_click()
    assert has_element?(view, "#atlas-workspace[data-settings-open=true]")
    assert render(view) =~ "Existing datasets are kept"

    view |> element("button[phx-click=settings_tab][phx-value-tab=services]") |> render_click()
    view |> element("input[phx-click=toggle_service][phx-value-name=photon]") |> render_click()
    assert render(view) =~ "Apply changes (2)"

    view |> element("button[phx-click=discard_settings_changes]") |> render_click()
    assert RegionSelection.active_names() == ["gf:asia"]
    assert has_element?(view, "button[phx-click=apply_selection][disabled]")
    refute render(view) =~ "Pending changes"

    view |> element("header button[phx-click=select_tab][phx-value-tab=search]") |> render_click()
    assert has_element?(view, "#atlas-workspace[data-settings-open=false]")
    assert has_element?(view, "#map[phx-hook=Map]")
  end

  test "applying an empty selection clears the pending state", %{conn: conn} do
    RegionSelection.clear()
    RegionSelection.toggle("gf:asia")
    RegionSelection.mark_applied!()
    RegionSelection.clear()
    {:ok, view, _} = open_settings(conn)

    assert render(view) =~ "Pending changes"
    view |> element("button[phx-click=apply_selection]") |> render_click()
    assert RegionSelection.applied_names() == []
    refute RegionSelection.pending_change?()
    assert has_element?(view, "button[phx-click=apply_selection][disabled]")
    assert render(view) =~ "Region selection cleared. Existing datasets are kept."
  end

  test "basemap explains immediate saving and links to pending changes", %{conn: conn} do
    RegionSelection.clear()
    RegionSelection.mark_applied!()
    RegionSelection.toggle("gf:asia")
    {:ok, view, _} = open_settings(conn)
    view |> element("button[phx-click=settings_tab][phx-value-tab=basemap]") |> render_click()
    assert render(view) =~ "Map appearance is saved immediately"
    assert render(view) =~ "Review 1 pending"
    refute has_element?(view, "button[phx-click=apply_selection]")
    view |> element("footer button[phx-click=settings_tab]") |> render_click()
    assert has_element?(view, "button[phx-click=apply_selection]")
  end

  test "service help describes purpose instead of showing a log line", %{conn: conn} do
    Atlas.Settings.set("transit_backend", "otp")
    {:ok, view, _} = open_settings(conn)
    view |> element("button[phx-click=settings_tab][phx-value-tab=services]") |> render_click()
    view |> element("button[phx-click=toggle_info][phx-value-name=otp]") |> render_click()
    assert render(view) =~ "Combines public transport timetables with walking connections"
    assert has_element?(view, ~s(input[aria-label="Enable OpenTripPlanner"]))
  end

  test "coverage opens asynchronously and closes without changing the selection", %{conn: conn} do
    before = RegionSelection.active_names()
    {:ok, view, _} = open_settings(conn)
    render_hook(view, "open_service_coverage", %{name: "libpostal"})
    assert has_element?(view, "#service-coverage-dialog[role=dialog]")
    html = render_async(view)
    assert html =~ "does not install a separate map dataset"
    assert RegionSelection.active_names() == before
    render_hook(view, "close_service_coverage", %{})
    refute has_element?(view, "#service-coverage-dialog")
  end

  test "MOTIS and OTP share an exclusive selector, with only the selected service card", %{
    conn: conn
  } do
    Atlas.Settings.set("transit_backend", "motis")
    {:ok, view, _} = open_settings(conn)
    view |> element("button[phx-value-tab=services]") |> render_click()
    assert has_element?(view, ~s(input[type=radio][value=motis][checked]))
    assert has_element?(view, ~s|input[type=radio][value=otp]:not([checked])|)
    assert has_element?(view, ~s(input[aria-label="Enable MOTIS"]))
    refute has_element?(view, ~s(input[aria-label="Enable OpenTripPlanner"]))
    assert render(view) =~ "Changes apply immediately"
  end

  test "failed switch keeps previous engine selected and shows the cause", %{conn: conn} do
    Atlas.Settings.set("transit_backend", "otp")
    start_supervised!({Atlas.Control.DockerCompose, runner: fn _, _ -> {"stop denied", 1} end})
    {:ok, view, _} = open_settings(conn)
    view |> element("button[phx-value-tab=services]") |> render_click()
    view |> element("input[type=radio][value=motis]") |> render_click()
    html = render_async(view)
    assert html =~ "stop denied"
    assert has_element?(view, ~s(input[type=radio][value=otp][checked]))
    refute has_element?(view, ~s(input[aria-label="Enable MOTIS"]))
  end
end
