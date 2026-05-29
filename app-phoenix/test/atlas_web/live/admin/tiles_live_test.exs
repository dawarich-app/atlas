defmodule AtlasWeb.Admin.TilesLiveTest do
  use AtlasWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Atlas.Settings

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

  test "GET /admin/tiles renders the settings form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/tiles")

    assert html =~ "Tiles"
    assert html =~ "Tiles URL"
    assert html =~ "Theme"
    assert html =~ "Download new tile pack"
  end

  test "form pre-fills existing tiles_url and theme settings", %{conn: conn} do
    Settings.set("tiles_url", "https://example.com/style.json")
    Settings.set("tiles_theme", "atlas-dark")

    {:ok, _view, html} = live(conn, ~p"/admin/tiles")

    assert html =~ "https://example.com/style.json"
    # The dark theme option is selected.
    assert html =~ ~s(value="atlas-dark" selected)
  end

  test "save event persists tiles_url and theme", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/tiles")

    view
    |> form("form[phx-submit=save]", %{
      "tiles_url" => "https://tiles.example/region.pmtiles",
      "theme" => "atlas-dark"
    })
    |> render_submit()

    assert Settings.get("tiles_url") == "https://tiles.example/region.pmtiles"
    assert Settings.get("tiles_theme") == "atlas-dark"
  end

  test "download event with empty URL flashes an error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/tiles")

    html =
      view
      |> form("form[phx-submit=download]", %{"url" => "   "})
      |> render_submit()

    assert html =~ "Provide a tile pack URL"
  end

  test "progress messages update the progress bar", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/tiles")

    job_id = Ecto.UUID.generate()
    send(view.pid, {:start, job_id, "https://tiles.example", "/tmp/x"})
    send(view.pid, {:progress, job_id, 0.42})

    html = render(view)
    assert html =~ ~s(<progress class="progress mt-2")
  end
end
