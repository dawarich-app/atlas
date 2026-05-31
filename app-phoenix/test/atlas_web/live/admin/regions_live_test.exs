defmodule AtlasWeb.Admin.RegionsLiveTest do
  use AtlasWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Atlas.Control.RegionSelection
  alias Atlas.Repo

  setup do
    System.put_env("ADMIN_USERNAME", "admin")
    System.put_env("ADMIN_PASSWORD", "s3cret")

    on_exit(fn ->
      Enum.each(~w[ADMIN_USERNAME ADMIN_PASSWORD], &System.delete_env/1)
    end)

    conn =
      build_conn()
      |> put_req_header("authorization", "Basic " <> Base.encode64("admin:s3cret"))

    {:ok, conn: conn}
  end

  test "GET /admin/regions lists region presets from priv/regions/", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/regions")

    assert html =~ "Regions"
    # Shipping presets should render as chips
    for label <- ~w[berlin germany europe planet] do
      assert html =~ label
    end
  end

  test "toggle event flips a region between selected/unselected", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/regions")

    html = view |> render_click("toggle", %{"name" => "berlin"})
    # When selected, the chip uses btn-primary class
    assert html =~ "btn-primary"

    html2 = view |> render_click("toggle", %{"name" => "berlin"})
    # Toggling again returns to outline style
    assert html2 =~ "btn-outline"
  end

  test "save event persists the selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/regions")

    view |> render_click("toggle", %{"name" => "berlin"})
    view |> render_click("toggle", %{"name" => "germany"})
    view |> render_click("save", %{})

    saved =
      RegionSelection
      |> Repo.all()
      |> Enum.map(& &1.region_name)
      |> Enum.sort()

    assert saved == ~w[berlin germany]
  end

  test "save event broadcasts {:regions_changed, names}", %{conn: conn} do
    Phoenix.PubSub.subscribe(Atlas.PubSub, "admin:regions")

    {:ok, view, _html} = live(conn, ~p"/admin/regions")
    view |> render_click("toggle", %{"name" => "berlin"})
    view |> render_click("save", %{})

    assert_receive {:regions_changed, ["berlin"]}, 500
  end

  test "LiveView reacts to {:regions_changed} broadcast", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/regions")

    # Insert directly then broadcast — simulating another tab.
    Repo.insert!(%RegionSelection{region_name: "berlin", active: true, position: 0})
    send(view.pid, {:regions_changed, ["berlin"]})

    html = render(view)
    assert html =~ "berlin"
  end

  test "save replaces previous selection", %{conn: conn} do
    Repo.insert!(%RegionSelection{region_name: "stale", active: true, position: 0})

    {:ok, view, _html} = live(conn, ~p"/admin/regions")
    # Drop the stale entry — it was loaded as `selected` on mount.
    view |> render_click("toggle", %{"name" => "stale"})
    view |> render_click("toggle", %{"name" => "berlin"})
    view |> render_click("save", %{})

    names = RegionSelection |> Repo.all() |> Enum.map(& &1.region_name)
    assert "stale" not in names
    assert "berlin" in names
  end
end
