defmodule Atlas.Control.OnboardingTest do
  use Atlas.DataCase, async: false

  alias Atlas.Control.{Onboarding, RegionSelection, Seeder, Service}
  alias Atlas.Settings

  defp draft(capabilities \\ ["routing"]) do
    %{"capabilities" => capabilities, "regions" => ["berlin"], "backend" => "motis", "step" => 3}
  end

  defp coordinator(opts \\ []) do
    parent = self()

    start_supervised!(
      {Onboarding,
       Keyword.merge(
         [
           preflight: fn -> [%{status: :ok}] end,
           apply: fn regions, opts ->
             send(parent, {:apply, regions, opts})
             {:ok, "test-job"}
           end,
           enable: fn name ->
             send(parent, {:enabled, name})
             :ok
           end,
           snapshot: fn _ -> %{ready?: false, enabled?: true} end
         ],
         opts
       )}
    )

    Phoenix.PubSub.subscribe(Atlas.PubSub, Onboarding.topic())
  end

  test "first run requires a fresh seeded installation and respects skip" do
    refute Onboarding.first_run?()

    for service <- Seeder.known_services(),
        do: Repo.insert!(%Service{name: service.name, profile: service.profile})

    assert Onboarding.first_run?()
    Onboarding.dismiss()
    refute Onboarding.first_run?()
  end

  test "existing installed data does not trigger setup" do
    for service <- Seeder.known_services(),
        do: Repo.insert!(%Service{name: service.name, profile: service.profile, disk_bytes: 10})

    refute Onboarding.first_run?()
  end

  test "draft does not change Settings region selection or transit engine" do
    RegionSelection.toggle("germany")
    Settings.set("transit_backend", "otp")
    Onboarding.save_draft(draft())
    assert Onboarding.draft() == draft()
    assert RegionSelection.active_names() == ["germany"]
    assert Settings.transit_backend() == "otp"
  end

  test "capabilities include dependencies and exactly one transit engine" do
    assert Enum.sort(Onboarding.services(draft(~w(search places routing transit)))) ==
             ~w(motis overpass photon valhalla)

    assert {:error, _} = Onboarding.validate(%{draft() | "capabilities" => []})
    assert :ok = Onboarding.validate(%{draft(["transit"]) | "regions" => ["germany"]})
    assert :ok = Onboarding.validate(draft(["transit"]))
  end

  test "missing timetables warn only for affected regions and do not block installation" do
    catalog = Atlas.Control.RegionCatalog.all()
    choice = %{draft(["transit"]) | "regions" => ["berlin", "germany"]}
    assert Enum.map(Onboarding.missing_transit_regions(choice, catalog), & &1.name) == ["germany"]
    assert Onboarding.missing_transit_regions(draft(["routing"]), catalog) == []
    assert Onboarding.missing_transit_regions(draft(["transit"]), catalog) == []
    coordinator()
    assert :ok = Onboarding.install(choice)
    assert_receive {:apply, ["berlin", "germany"], [services: ["photon", "motis"]]}
  end

  test "Photon starts immediately while regional services wait for data and duplicate starts are rejected" do
    coordinator()
    assert :ok = Onboarding.install(draft())
    assert_receive {:apply, ["berlin"], [services: ["photon", "valhalla"]]}
    assert_receive {:enabled, "photon"}
    refute_received {:enabled, "valhalla"}
    assert {:error, _} = Onboarding.install(draft())
    send(Onboarding, {:apply_done, %{job_id: "another-job"}})
    _ = :sys.get_state(Onboarding)
    refute_received {:enabled, _}
    send(Onboarding, {:apply_done, %{job_id: "test-job"}})
    assert_receive {:enabled, "valhalla"}
    refute_received {:enabled, "photon"}
    assert_receive {:setup_job, %{"status" => "waiting"}}
    assert Onboarding.job()["status"] == "waiting"
  end

  test "data failure survives reload and retry uses the same regions" do
    coordinator()
    :ok = Onboarding.install(draft())
    send(Onboarding, {:apply_error, %{job_id: "test-job", reason: "disk full"}})
    _ = :sys.get_state(Onboarding)
    assert Onboarding.job()["error"] == "disk full"
    assert :ok = Onboarding.install(draft())
    assert_receive {:apply, ["berlin"], _}
  end

  test "interrupted setup becomes retryable after server restart" do
    Settings.set("setup_job", Jason.encode!(%{"status" => "preparing", "draft" => draft()}))
    coordinator()
    assert Onboarding.job()["status"] == "failed"
    assert Onboarding.job()["error"] =~ "interrupted"
  end

  test "ready services finish setup without reapplying data for search only" do
    coordinator(snapshot: fn _ -> %{ready?: true, enabled?: true} end)
    assert :ok = Onboarding.install(draft(["search"]))
    assert_receive {:enabled, "photon"}
    assert_receive {:setup_job, %{"status" => "complete"}}
    refute_received {:apply, _, _}
  end

  test "retry starts only the failed service and never downloads regions again" do
    coordinator()
    :ok = Onboarding.install(draft())
    assert_receive {:apply, _, _}
    send(Onboarding, {:apply_done, %{job_id: "test-job"}})
    assert_receive {:enabled, "photon"}
    assert_receive {:enabled, "valhalla"}
    assert_receive {:setup_job, %{"status" => "waiting"}}
    _ = :sys.get_state(Onboarding)
    assert :ok = Onboarding.retry_service("valhalla")
    assert_receive {:enabled, "valhalla"}
    refute_received {:enabled, "photon"}
    refute_received {:apply, _, _}
    assert {:error, _} = Onboarding.retry_service("otp")
  end

  test "failed environment checks prevent all installation work" do
    coordinator(preflight: fn -> [%{status: :error}] end)
    assert {:error, _} = Onboarding.install(draft())
    refute_received {:apply, _, _}
    assert Onboarding.job() == nil
  end
end
