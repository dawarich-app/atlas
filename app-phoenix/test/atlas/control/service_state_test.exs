defmodule Atlas.Control.ServiceStateTest do
  use Atlas.DataCase, async: false
  alias Atlas.Control.{Service, ServiceState}

  defmodule DummyParser do
    @behaviour Atlas.Control.Parser

    @impl true
    def init, do: %{}

    @impl true
    def feed("DONE", _acc),
      do:
        {%{phase: "ready", progress: 1.0, last_log_line: "DONE", ready: true}, %{}}

    def feed(line, _acc),
      do:
        {%{phase: "running", progress: 0.5, last_log_line: line, ready: false}, %{}}
  end

  setup do
    start_supervised!({Registry, keys: :unique, name: Atlas.Control.Registry})

    {:ok, _row} =
      Repo.insert(%Service{
        name: "photon",
        profile: "geocoding",
        enabled: false,
        status: :unknown
      })

    {:ok, _pid} =
      start_supervised({ServiceState, {"photon", "geocoding", DummyParser}})

    :ok
  end

  test "feed/2 updates parser state and broadcasts a snapshot" do
    Phoenix.PubSub.subscribe(Atlas.PubSub, "control:service:photon")
    ServiceState.feed("photon", "starting...")
    assert_receive {:service_update, %{phase: "running", progress: 0.5, last_log: "starting..."}}
  end

  test "ready signal sticks across subsequent feeds" do
    ServiceState.feed("photon", "DONE")
    # second non-ready line shouldn't clear ready?
    ServiceState.feed("photon", "noise")
    snap = ServiceState.snapshot("photon")
    assert snap.ready? == true
  end

  test "snapshot/1 returns hydrated fields from DB" do
    snap = ServiceState.snapshot("photon")
    assert snap.name == "photon"
    assert snap.profile == "geocoding"
    assert snap.enabled? == false
    assert snap.status == :unknown
  end

  test "feed/2 broadcasts on control:status fan-in topic" do
    Phoenix.PubSub.subscribe(Atlas.PubSub, "control:status")
    ServiceState.feed("photon", "starting...")
    assert_receive :status_changed
  end

  test "set_auto_update/2 persists the flag and broadcasts" do
    Phoenix.PubSub.subscribe(Atlas.PubSub, "control:service:photon")
    assert :ok = ServiceState.set_auto_update("photon", true)
    assert_receive {:service_update, %{auto_update_enabled?: true}}

    row = Repo.get_by!(Service, name: "photon")
    assert row.auto_update_enabled == true

    assert :ok = ServiceState.set_auto_update("photon", false)
    assert_receive {:service_update, %{auto_update_enabled?: false}}
    assert Repo.get_by!(Service, name: "photon").auto_update_enabled == false
  end

  describe "enable/disable compose error propagation" do
    defp start_compose(result) do
      start_supervised!({Atlas.Control.DockerCompose, runner: fn _cmd, _args -> result end})
    end

    test "enable returns immediately as :starting even when compose is slow" do
      test_pid = self()

      start_supervised!(
        {Atlas.Control.DockerCompose,
         runner: fn _cmd, _args ->
           send(test_pid, {:compose_started, self()})

           receive do
             :proceed -> :ok
           after
             10_000 -> :ok
           end

           {"ok", 0}
         end}
      )

      Repo.get_by!(Service, name: "photon")
      |> Service.changeset(%{last_error: "old"})
      |> Repo.update!()

      # The call must NOT block on the (potentially minutes-long) compose run —
      # a docker image pull must not freeze the LiveView for its duration.
      {elapsed_us, :ok} = :timer.tc(fn -> ServiceState.enable("photon") end)
      assert elapsed_us < 500_000

      snap = ServiceState.snapshot("photon")
      assert snap.enabled? == true
      assert snap.status == :starting
      assert snap.last_error == nil
      assert Repo.get_by!(Service, name: "photon").last_error == nil

      assert_receive {:compose_started, compose_pid}, 1_000
      send(compose_pid, :proceed)
    end

    test "enable failure → :error status with persisted last_error" do
      start_compose({"'compose' is not a docker command", 1})
      Phoenix.PubSub.subscribe(Atlas.PubSub, "control:service:photon")

      assert :ok = ServiceState.enable("photon")

      assert_receive {:service_update, %{status: :error, last_error: err}}, 1_000
      assert err =~ "not a docker command"

      snap = ServiceState.snapshot("photon")
      assert snap.status == :error
      assert snap.last_error =~ "not a docker command"

      assert Repo.get_by!(Service, name: "photon").last_error =~ "not a docker command"
    end

    test "enable with no DockerCompose process → :error, not a crash" do
      Phoenix.PubSub.subscribe(Atlas.PubSub, "control:service:photon")

      assert :ok = ServiceState.enable("photon")

      assert_receive {:service_update, %{status: :error, last_error: err}}, 1_000
      assert err =~ "control plane"
    end

    test "disable failure keeps previous status and records last_error" do
      start_supervised!(
        {Atlas.Control.DockerCompose,
         runner: fn
           _cmd, ["compose", "up" | _] -> {"ok", 0}
           _cmd, ["compose", "stop" | _] -> {"permission denied", 1}
         end}
      )

      Phoenix.PubSub.subscribe(Atlas.PubSub, "control:service:photon")

      assert :ok = ServiceState.enable("photon")
      ServiceState.feed("photon", "DONE")
      assert %{status: :ready} = ServiceState.snapshot("photon")

      assert :ok = ServiceState.disable("photon")

      assert_receive {:service_update, %{enabled?: false, last_error: err}} when err != nil,
                     1_000

      snap = ServiceState.snapshot("photon")
      assert snap.enabled? == false
      assert snap.status == :ready
      assert snap.last_error =~ "permission denied"
    end

    test "disable success → :stopped" do
      start_compose({"ok", 0})
      Phoenix.PubSub.subscribe(Atlas.PubSub, "control:service:photon")

      assert :ok = ServiceState.disable("photon")

      assert_receive {:service_update, %{status: :stopped}}, 1_000

      snap = ServiceState.snapshot("photon")
      assert snap.status == :stopped
      assert snap.last_error == nil
    end
  end

  describe "reconcile/1 — desired state vs actual containers" do
    test "starts an enabled service whose container is gone" do
      test_pid = self()

      start_supervised!(
        {Atlas.Control.DockerCompose,
         runner: fn
           _cmd, ["compose", "ps" | _] = args ->
             send(test_pid, {:compose, args})
             {"\n", 0}

           _cmd, ["compose", "up" | _] = args ->
             send(test_pid, {:compose, args})
             {"ok", 0}
         end}
      )

      Repo.get_by!(Service, name: "photon")
      |> Service.changeset(%{enabled: true, status: :ready})
      |> Repo.update!()

      # Restart the actor so it hydrates the enabled/ready row.
      stop_supervised!(ServiceState)
      start_supervised!({ServiceState, {"photon", "geocoding", DummyParser}})

      Phoenix.PubSub.subscribe(Atlas.PubSub, "control:service:photon")
      assert :ok = ServiceState.reconcile("photon")

      assert_receive {:compose, ["compose", "ps" | _]}, 1_000
      assert_receive {:compose, ["compose", "up", "-d", "photon"]}, 1_000
      assert_receive {:service_update, %{status: :starting}}, 1_000
    end

    test "corrects a stale running-ish status when nothing is running and service is disabled" do
      start_supervised!(
        {Atlas.Control.DockerCompose, runner: fn _cmd, _args -> {"\n", 0} end}
      )

      Repo.get_by!(Service, name: "photon")
      |> Service.changeset(%{enabled: false, status: :ready})
      |> Repo.update!()

      stop_supervised!(ServiceState)
      start_supervised!({ServiceState, {"photon", "geocoding", DummyParser}})

      Phoenix.PubSub.subscribe(Atlas.PubSub, "control:service:photon")
      assert :ok = ServiceState.reconcile("photon")

      assert_receive {:service_update, %{status: :stopped}}, 1_000
    end

    test "upgrades a stale stopped status when the container is actually running" do
      start_supervised!(
        {Atlas.Control.DockerCompose, runner: fn _cmd, _args -> {"3f2a1b\n", 0} end}
      )

      Repo.get_by!(Service, name: "photon")
      |> Service.changeset(%{enabled: true, status: :stopped})
      |> Repo.update!()

      stop_supervised!(ServiceState)
      start_supervised!({ServiceState, {"photon", "geocoding", DummyParser}})

      Phoenix.PubSub.subscribe(Atlas.PubSub, "control:service:photon")
      assert :ok = ServiceState.reconcile("photon")

      assert_receive {:service_update, %{status: :starting}}, 1_000
    end

    test "probe errors leave state untouched" do
      start_supervised!(
        {Atlas.Control.DockerCompose, runner: fn _cmd, _args -> {"permission denied", 1} end}
      )

      Phoenix.PubSub.subscribe(Atlas.PubSub, "control:service:photon")
      assert :ok = ServiceState.reconcile("photon")

      refute_receive {:service_update, _}, 200
      assert %{status: :unknown} = ServiceState.snapshot("photon")
    end
  end
end
