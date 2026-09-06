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
       osmium_convert: fn dir, _in, out ->
         File.write!(Path.expand(out, dir), "bz2")
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
       osmium_convert: fn dir, _in, out ->
         File.write!(Path.expand(out, dir), "bz2")
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

  defp ingesting_timeline(services, snapshots) do
    now = DateTime.utc_now()

    base =
      ["Germany"]
      |> Atlas.Control.ApplyTimeline.start(services, now)
      |> Atlas.Control.ApplyTimeline.apply_event({:apply_progress, %{phase: :restarting}}, now)
      |> Atlas.Control.ApplyTimeline.apply_event({:apply_restarting, services}, now)

    Enum.reduce(snapshots, base, fn {name, phase, progress}, acc ->
      Atlas.Control.ApplyTimeline.apply_event(
        acc,
        {:service_update,
         %{
           name: name,
           status: :running,
           phase: phase,
           progress: progress,
           ready?: false,
           last_error: nil
         }},
        now
      )
    end)
  end

  defp timeline_html(view, timeline) do
    send(view.pid, {:timeline, timeline})

    view
    |> element(~s([data-role="apply-timeline"]))
    |> render()
  end

  test "the admin apply page renders the same timeline detail", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/apply")

    html =
      timeline_html(
        view,
        ingesting_timeline(["otp"], [{"otp", "building-graph", 0.34}])
      )

    # building-graph, not building-tiles: OTP's log carries a real "(N%)", so a
    # percentage here is measured. Valhalla's building-tiles number is
    # fabricated by the parser and is deliberately never rendered.
    assert html =~ "building-graph"
    assert html =~ "34%"
    assert html =~ "step 5 of 5"
  end

  test "a stage whose percentage was invented renders the phase and no number", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/apply")

    # Parsers.Overpass hardcodes 0.6 for every "ingesting" line — a phase
    # marker, not a measurement. The row must show the phase text alone.
    html =
      timeline_html(
        view,
        ingesting_timeline(["overpass", "otp"], [
          {"overpass", "ingesting", 0.6},
          {"otp", "building-graph", 0.12}
        ])
      )

    assert html =~ "ingesting"
    refute html =~ "60%"

    # …while OTP's building-graph number IS read out of its log, so it renders.
    assert html =~ "building-graph"
    assert html =~ "12%"
  end
end
