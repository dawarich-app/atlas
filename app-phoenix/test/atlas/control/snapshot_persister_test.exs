defmodule Atlas.Control.SnapshotPersisterTest do
  use Atlas.DataCase, async: false

  alias Atlas.Control.{Seeder, Service, ServiceState, ServiceSupervisor, SnapshotPersister}

  setup do
    start_supervised!({Registry, keys: :unique, name: Atlas.Control.Registry})
    start_supervised!(ServiceSupervisor)
    Seeder.seed_and_start!()
    :ok
  end

  test "flush_now/0 writes runtime fields back to services table" do
    ServiceState.feed("photon", "Started PhotonApplication in 1.2 seconds")

    # Make sure the cast has been processed before flushing.
    _ = ServiceState.snapshot("photon")

    SnapshotPersister.flush_now()

    row = Repo.get_by!(Service, name: "photon")
    refute is_nil(row.last_seen_at)
    refute is_nil(row.last_log)
  end

  test "flush_now/0 is safe when a ServiceState is not running" do
    # Stop one of the ServiceStates to simulate a not-yet-started service.
    [{pid, _}] = Registry.lookup(Atlas.Control.Registry, "photon")
    DynamicSupervisor.terminate_child(ServiceSupervisor, pid)

    # Should not raise even though photon's ServiceState is gone.
    assert :ok = SnapshotPersister.flush_now()
  end

  test "flush_now/0 leaves rows untouched when no parser output yet" do
    before = Repo.get_by!(Service, name: "valhalla")
    SnapshotPersister.flush_now()
    after_row = Repo.get_by!(Service, name: "valhalla")

    assert before.phase == after_row.phase
    assert before.progress == after_row.progress
  end
end
