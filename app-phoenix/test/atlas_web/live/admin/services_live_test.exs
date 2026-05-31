defmodule AtlasWeb.Admin.ServicesLiveTest do
  use AtlasWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Atlas.Control.Service
  alias Atlas.Repo

  setup do
    System.put_env("ADMIN_USERNAME", "admin")
    System.put_env("ADMIN_PASSWORD", "s3cret")

    on_exit(fn ->
      Enum.each(~w[ADMIN_USERNAME ADMIN_PASSWORD], &System.delete_env/1)
    end)

    {:ok, _row} =
      Repo.insert(%Service{
        name: "photon",
        profile: "geocoding",
        enabled: false,
        status: :unknown
      })

    conn =
      build_conn()
      |> put_req_header("authorization", "Basic " <> Base.encode64("admin:s3cret"))

    {:ok, conn: conn}
  end

  test "GET /admin/services renders a card for each known service", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/services")

    assert html =~ "Services"
    # All 7 seeded services
    for name <- ~w[photon placeholder libpostal valhalla overpass otp whosonfirst] do
      assert html =~ name
    end

    # Card actions are present
    assert html =~ "Update now"
    assert html =~ "Auto-update cron"
  end

  test "schedule event with invalid cron flashes an error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/services")

    html =
      view
      |> render_submit("schedule", %{"name" => "photon", "cron" => "not a cron"})

    assert html =~ "Invalid cron expression"
  end

  test "schedule event with valid cron persists to the services row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/services")

    _html = view |> render_submit("schedule", %{"name" => "photon", "cron" => "0 3 * * *"})

    assert Repo.get_by!(Service, name: "photon").update_schedule_cron == "0 3 * * *"
  end

  test "service card shows last_error when status is error", %{conn: conn} do
    Repo.get_by(Service, name: "photon")
    |> Service.changeset(%{status: :error, last_error: "photon failed to start"})
    |> Repo.update!()

    {:ok, _view, html} = live(conn, ~p"/admin/services")

    assert html =~ "photon failed to start"
    assert html =~ ~s(data-error-line="true")
  end

  test "service card shows disk size when disk_bytes > 0", %{conn: conn} do
    Repo.get_by(Service, name: "photon")
    |> Service.changeset(%{disk_bytes: 2_500_000_000})
    |> Repo.update!()

    {:ok, _view, html} = live(conn, ~p"/admin/services")

    assert html =~ "Disk:"
    assert html =~ "GB"
  end

  test "service card disables Update now button when update is running", %{conn: conn} do
    Repo.get_by(Service, name: "photon")
    |> Service.changeset(%{last_update_status: "running"})
    |> Repo.update!()

    {:ok, _view, html} = live(conn, ~p"/admin/services")

    assert html =~ "Updating…"
  end

  test "service card includes phx-disable-with on toggle button", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/services")

    # Button shows disabling-while-toggling state
    assert html =~ "phx-disable-with"
  end

  test "schedule event with empty cron clears the field", %{conn: conn} do
    {:ok, _row} =
      Repo.get_by(Service, name: "photon")
      |> Service.changeset(%{update_schedule_cron: "0 3 * * *"})
      |> Repo.update()

    {:ok, view, _html} = live(conn, ~p"/admin/services")
    _html = view |> render_submit("schedule", %{"name" => "photon", "cron" => "  "})

    assert Repo.get_by!(Service, name: "photon").update_schedule_cron == nil
  end
end
