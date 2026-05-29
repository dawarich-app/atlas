defmodule Atlas.Control.Jobs.AutoUpdateScanTest do
  use Atlas.DataCase, async: false
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Control.{Service, Jobs.AutoUpdateScan, Jobs.UpdateService}

  setup do
    start_supervised!({Oban, Application.fetch_env!(:atlas, Oban) |> Keyword.put(:testing, :manual)})

    # Insert one service that is auto-update-eligible with a wildcard cron
    # ("matches every minute"), and one whose cron is "midnight only" so it
    # never matches at perform time.
    {:ok, _} =
      Repo.insert(%Service{
        name: "photon",
        profile: "geocoding",
        auto_update_enabled: true,
        update_schedule_cron: "* * * * *"
      })

    {:ok, _} =
      Repo.insert(%Service{
        name: "valhalla",
        profile: "routing",
        auto_update_enabled: true,
        update_schedule_cron: "0 0 1 1 *"
      })

    {:ok, _} =
      Repo.insert(%Service{
        name: "overpass",
        profile: "pois",
        auto_update_enabled: false,
        update_schedule_cron: "* * * * *"
      })

    {:ok, _} =
      Repo.insert(%Service{
        name: "libpostal",
        profile: "geocoding",
        auto_update_enabled: true,
        update_schedule_cron: "* * * * *",
        last_update_status: "running"
      })

    :ok
  end

  test "enqueues UpdateService for services whose cron matches now" do
    assert :ok = perform_job(AutoUpdateScan, %{})

    assert_enqueued worker: UpdateService, args: %{"name" => "photon"}
  end

  test "does not enqueue for services whose cron does not match" do
    perform_job(AutoUpdateScan, %{})

    refute_enqueued worker: UpdateService, args: %{"name" => "valhalla"}
  end

  test "does not enqueue for services where auto_update_enabled is false" do
    perform_job(AutoUpdateScan, %{})

    refute_enqueued worker: UpdateService, args: %{"name" => "overpass"}
  end

  test "does not enqueue for services already in last_update_status=running" do
    perform_job(AutoUpdateScan, %{})

    refute_enqueued worker: UpdateService, args: %{"name" => "libpostal"}
  end
end
