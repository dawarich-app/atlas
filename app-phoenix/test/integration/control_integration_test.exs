defmodule ControlIntegrationTest do
  use Atlas.DataCase, async: false

  @moduletag :integration

  alias Atlas.Control.{Service, ServiceState, SnapshotPersister}

  setup do
    start_supervised!(
      {Oban, Application.fetch_env!(:atlas, Oban) |> Keyword.put(:testing, :manual)}
    )

    start_supervised!(Atlas.Control.Supervisor)
    Atlas.Control.Supervisor.post_start()

    :ok
  end

  test "feed a Photon-ready line → SnapshotPersister flushes phase=ready to DB" do
    Phoenix.PubSub.subscribe(Atlas.PubSub, "control:service:photon")

    ServiceState.feed("photon", "2026-05-14 21:42:32,738 - root - INFO - Photon ready after 5.0 seconds")
    assert_receive {:service_update, %{ready?: true, phase: "ready"}}, 2_000

    SnapshotPersister.flush_now()

    row = Repo.get_by!(Service, name: "photon")
    assert row.phase == "ready"
  end
end
