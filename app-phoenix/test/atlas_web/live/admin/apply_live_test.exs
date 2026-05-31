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

    runner = fn data_dir, sources, output ->
      send(test_pid, {:runner_called, data_dir, sources, output})

      receive do
        :proceed -> :ok
      after
        2_000 -> :ok
      end

      :ok
    end

    start_supervised!(
      {RegionApplier,
       runner: runner,
       pbf_lookup: fn r -> "#{r}.osm.pbf" end,
       data_dir: "/tmp/atlas-test",
       output_path: "out.pbf"}
    )

    {:ok, view, _html} = live(conn, ~p"/admin/apply")
    view |> render_click("project", %{})
    html = view |> render_click("confirm_apply", %{})

    assert html =~ "Applying"
    assert_receive {:runner_called, "/tmp/atlas-test", ["berlin.osm.pbf"], "out.pbf"}, 1_000
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

    runner = fn _data_dir, sources, _output ->
      send(test_pid, {:runner_called, sources})
      :ok
    end

    start_supervised!(
      {RegionApplier,
       runner: runner,
       pbf_lookup: fn r -> "#{r}.osm.pbf" end,
       data_dir: "/tmp/atlas-test",
       output_path: "out.pbf"}
    )

    {:ok, view, _html} = live(conn, ~p"/admin/apply")
    view |> render_click("project", %{})
    html = view |> render_click("confirm_apply", %{})

    assert html =~ "Applying"
    assert_receive {:runner_called, ["berlin.osm.pbf"]}, 1_000
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
