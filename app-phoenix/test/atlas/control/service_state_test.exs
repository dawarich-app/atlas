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
end
