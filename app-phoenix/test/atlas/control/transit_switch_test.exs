defmodule Atlas.Control.TransitSwitchTest do
  use Atlas.DataCase, async: false
  alias Atlas.Control.{DockerCompose, Seeder, Service, ServiceState, ServiceSupervisor}

  setup do
    start_supervised!({Registry, keys: :unique, name: Atlas.Control.Registry})
    start_supervised!(ServiceSupervisor)
    :ok
  end

  defp control(fail_stop \\ false) do
    test = self()

    start_supervised!(
      {DockerCompose,
       runner: fn _, args ->
         send(test, {:command, args})

         if fail_stop and List.last(args) == "otp" and "stop" in args,
           do: {"cannot stop OTP", 1},
           else: {"", 0}
       end}
    )

    Seeder.seed_and_start!()
  end

  test "switch stops and verifies old engine before starting new; state and routing choice agree" do
    Atlas.Settings.set("transit_backend", "otp")
    control()
    assert {:ok, _} = DockerCompose.select_transit("motis")
    assert_received {:command, ["compose", "stop", "otp"]}
    assert_received {:command, ["compose", "ps", "-q", "--status", "running", "otp"]}
    assert_received {:command, ["compose", "up", "-d", "motis"]}
    assert Atlas.Settings.transit_backend() == "motis"
    assert ServiceState.snapshot("motis").enabled?
    refute ServiceState.snapshot("otp").enabled?
    assert Repo.get_by!(Service, name: "motis").enabled
    refute Repo.get_by!(Service, name: "otp").enabled
    assert {:error, _, _} = DockerCompose.restart("otp")
    refute_received {:command, ["compose", "restart", "otp"]}
    assert {:ok, _} = DockerCompose.select_transit("otp")
    assert Atlas.Settings.transit_backend() == "otp"
    refute ServiceState.snapshot("motis").enabled?
    assert ServiceState.snapshot("otp").enabled?
  end

  test "a stop failure preserves choice and never starts the alternative" do
    Atlas.Settings.set("transit_backend", "otp")
    control(true)
    assert {:error, 1, "cannot stop OTP"} = DockerCompose.select_transit("motis")
    assert Atlas.Settings.transit_backend() == "otp"
    refute_received {:command, ["compose", "up", "-d", "motis"]}
  end
end
