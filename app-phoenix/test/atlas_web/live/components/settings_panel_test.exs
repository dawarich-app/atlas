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
    assert html =~ "Control plane"
    assert html =~ "Settings"
    assert html =~ "Region"
    assert html =~ "Basemap"
    assert html =~ "Services"
    assert html =~ "Save &amp; apply selection"
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
    assert html =~ "#{total}/#{total}"
    refute html =~ "#{total + 1}/#{total}"
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

  test "the pending summary projects disk and first-boot hours for staged tools",
       %{conn: conn} do
    {:ok, view, _html} = open_settings(conn)

    view
    |> element("button[phx-click=settings_tab][phx-value-tab=services]")
    |> render_click()

    html =
      view
      |> element(~s(input[phx-click=toggle_service][phx-value-name=photon]))
      |> render_click()

    # The projection line shows a disk/hours estimate for the staged set.
    assert html =~ "GB"
    assert html =~ ~r/\dh|first boot/i
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
    |> element(~s([data-node="gf:asia"] > div[phx-click="toggle_region"]))
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

    assert render(view) =~ "Save &amp; apply selection"
    assert has_element?(view, "button[phx-click=apply_selection][disabled]")

    # A new selection re-arms the button.
    view
    |> element(~s([data-node="gf:africa"] > div[phx-click="toggle_region"]))
    |> render_click()

    assert render(view) =~ "Save &amp; apply (1)"
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
end
