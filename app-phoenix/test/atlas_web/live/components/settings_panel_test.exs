defmodule AtlasWeb.SettingsPanelTest do
  use AtlasWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Atlas.Control.RegionSelection
  alias Atlas.Repo

  test "settings panel renders four sections", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    # Section 1: tiles URL + theme
    assert html =~ "Tiles URL"
    assert html =~ "Theme"

    # Section 2: regions
    assert html =~ "Region"
    assert html =~ "Manage regions"

    # Section 3: basemap
    assert html =~ "Basemap"
    assert html =~ "Source"
  end

  test "regions section lists active region selections", %{conn: conn} do
    Repo.insert!(%RegionSelection{region_name: "berlin", active: true, position: 0})
    Repo.insert!(%RegionSelection{region_name: "germany", active: true, position: 1})

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "berlin"
    assert html =~ "germany"
  end

  test "basemap section shows external source for http URL", %{conn: conn} do
    Atlas.Settings.set("tiles_url", "https://example.com/style.json")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "external"
  end

  test "basemap section shows sidecar source for atlas-control URL", %{conn: conn} do
    Atlas.Settings.set("tiles_url", "http://atlas-control:5000/tiles.pmtiles")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "sidecar"
  end
end
