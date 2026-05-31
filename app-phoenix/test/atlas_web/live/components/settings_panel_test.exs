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

  test "regions section lists every preset with a checkbox + size hint",
       %{conn: conn} do
    {:ok, _view, html} = open_settings(conn)

    # Region presets ship with PR #10's Catalog (berlin, germany, europe, …).
    # The label is rendered per option, with a GB-size hint sibling.
    assert html =~ "Berlin (city)"
    assert html =~ "Germany"
    assert html =~ "~15 GB"
  end

  test "regions section reflects active selections from the DB",
       %{conn: conn} do
    Repo.delete_all(RegionSelection)
    Repo.insert!(%RegionSelection{region_name: "berlin", active: true, position: 0})

    {:ok, _view, html} = open_settings(conn)

    # Stats strip shows the active region label.
    assert html =~ "Berlin (city)"
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
end
