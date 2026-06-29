defmodule AtlasWeb.Admin.ApplyLiveTest do
  use AtlasWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Atlas.Control.{RegionApplier, RegionSelection}
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

  test "GET /admin/apply with no selection shows an empty-state link", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/apply")

    assert html =~ "Apply Regions"
    assert html =~ "No regions selected"
  end

  test "GET /admin/apply with selection lists regions and an Apply button", %{conn: conn} do
    Repo.insert!(%RegionSelection{region_name: "berlin", active: true, position: 0})
    Repo.insert!(%RegionSelection{region_name: "germany", active: true, position: 1})

    {:ok, _view, html} = live(conn, ~p"/admin/apply")

    assert html =~ "berlin"
    assert html =~ "germany"
    assert html =~ "Apply"
  end

  test "project + confirm_apply invokes RegionApplier and flips state to applying", %{conn: conn} do
    Repo.insert!(%RegionSelection{region_name: "berlin", active: true, position: 0})

    test_pid = self()
    tmp = Path.join(System.tmp_dir!(), "apply-live-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    downloader = fn url, dest, _progress ->
      send(test_pid, {:download_called, url, dest})

      receive do
        :proceed -> :ok
      after
        2_000 -> :ok
      end

      File.mkdir_p!(Path.dirname(dest))
      File.write!(dest, "pbf")
      {:ok, dest}
    end

    Phoenix.PubSub.subscribe(Atlas.PubSub, RegionApplier.topic())

    start_supervised!(
      {RegionApplier,
       downloader: downloader,
       osmium_convert: fn _dir, _in, out ->
         File.write!(Path.expand(out, tmp), "bz2")
         {:ok, "ok"}
       end,
       restart: fn _names -> :ok end,
       catalog_find: fn name ->
         %Atlas.Control.RegionCatalog{
           name: name,
           label: name,
           pbf_urls: ["http://example.test/#{name}.osm.pbf"]
         }
       end,
       data_dir: tmp}
    )

    {:ok, view, _html} = live(conn, ~p"/admin/apply")
    view |> render_click("project", %{})
    html = view |> render_click("confirm_apply", %{})

    assert html =~ "Applying"
    assert_receive {:download_called, "http://example.test/berlin.osm.pbf", _dest}, 1_000
    assert_receive {:apply_done, _}, 4_000
  end

  test "confirm_apply errors when RegionApplier is not running", %{conn: conn} do
    Repo.insert!(%RegionSelection{region_name: "berlin", active: true, position: 0})

    {:ok, _} =
      Atlas.Repo.insert(%Atlas.Control.Service{
        name: "photon",
        profile: "geocoding",
        enabled: true
      })

    {:ok, view, _html} = live(conn, ~p"/admin/apply")
    view |> render_click("project", %{})
    html = view |> render_click("confirm_apply", %{})

    assert html =~ "Failed to start apply" or html =~ "noproc"
  end

  test "project event shows projection table with disk + hours", %{conn: conn} do
    Repo.insert!(%RegionSelection{region_name: "berlin", active: true, position: 0})

    {:ok, _} =
      Atlas.Repo.insert(%Atlas.Control.Service{
        name: "photon",
        profile: "geocoding",
        enabled: true
      })

    {:ok, view, _html} = live(conn, ~p"/admin/apply")
    html = view |> render_click("project", %{})

    assert html =~ "Projection"
    assert html =~ "photon"
    assert html =~ "Confirm Apply"
  end

  test "confirm_apply is rejected when not in projected state", %{conn: conn} do
    Repo.insert!(%RegionSelection{region_name: "berlin", active: true, position: 0})

    {:ok, view, _html} = live(conn, ~p"/admin/apply")
    html = view |> render_click("confirm_apply", %{})

    assert html =~ "Project regions before confirming"
  end

  test "confirm_apply after project flips state to applying", %{conn: conn} do
    Repo.insert!(%RegionSelection{region_name: "berlin", active: true, position: 0})

    test_pid = self()
    tmp = Path.join(System.tmp_dir!(), "apply-live-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    downloader = fn url, dest, _progress ->
      send(test_pid, {:download_called, url})
      File.mkdir_p!(Path.dirname(dest))
      File.write!(dest, "pbf")
      {:ok, dest}
    end

    start_supervised!(
      {RegionApplier,
       downloader: downloader,
       osmium_convert: fn _dir, _in, out ->
         File.write!(Path.expand(out, tmp), "bz2")
         {:ok, "ok"}
       end,
       restart: fn _names -> :ok end,
       catalog_find: fn name ->
         %Atlas.Control.RegionCatalog{
           name: name,
           label: name,
           pbf_urls: ["http://example.test/#{name}.osm.pbf"]
         }
       end,
       data_dir: tmp}
    )

    Phoenix.PubSub.subscribe(Atlas.PubSub, RegionApplier.topic())

    {:ok, view, _html} = live(conn, ~p"/admin/apply")
    view |> render_click("project", %{})
    html = view |> render_click("confirm_apply", %{})

    assert html =~ "Applying"
    assert_receive {:download_called, "http://example.test/berlin.osm.pbf"}, 1_000
    assert_receive {:apply_done, _}, 2_000
  end

  test "project event renders region_not_found error for unknown region", %{conn: conn} do
    Repo.insert!(%RegionSelection{region_name: "atlantis", active: true, position: 0})

    {:ok, view, _html} = live(conn, ~p"/admin/apply")
    html = view |> render_click("project", %{})

    assert html =~ "Region not available"
    assert html =~ "atlantis"
  end

  test "cancel_projection returns to idle state", %{conn: conn} do
    Repo.insert!(%RegionSelection{region_name: "berlin", active: true, position: 0})

    {:ok, view, _html} = live(conn, ~p"/admin/apply")
    view |> render_click("project", %{})
    html = view |> render_click("cancel_projection", %{})

    refute html =~ "Confirm Apply"
    assert html =~ "Project"
  end
end
