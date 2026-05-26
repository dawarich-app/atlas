defmodule Atlas.Control.Jobs.UpdateServiceTest do
  use Atlas.DataCase, async: false
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Control.{DockerCompose, Service, Jobs.UpdateService}

  setup do
    start_supervised!({Oban, Application.fetch_env!(:atlas, Oban) |> Keyword.put(:testing, :manual)})

    {:ok, _} =
      Repo.insert(%Service{
        name: "photon",
        profile: "geocoding",
        auto_update_enabled: true
      })

    :ok
  end

  defp start_compose(runner) do
    # DockerCompose is a named GenServer; stop any running instance before
    # starting the test-scoped one with the stub runner.
    if pid = GenServer.whereis(DockerCompose) do
      GenServer.stop(pid)
    end

    start_supervised!({DockerCompose, runner: runner})
  end

  test "successful update sets last_update_status=success and dataset_updated_at" do
    start_compose(fn _cmd, _args -> {"pulled", 0} end)

    assert :ok = perform_job(UpdateService, %{"name" => "photon"})

    row = Repo.get_by!(Service, name: "photon")
    assert row.last_update_status == "success"
    refute is_nil(row.dataset_updated_at)
    assert is_integer(row.last_update_duration_s)
    assert row.auto_update_enabled == true
    assert is_nil(row.last_update_error)
  end

  test "failed update sets last_update_status=failure and disables auto_update_enabled" do
    start_compose(fn _cmd, _args -> {"boom", 1} end)

    assert {:error, :update_failed} = perform_job(UpdateService, %{"name" => "photon"})

    row = Repo.get_by!(Service, name: "photon")
    assert row.last_update_status == "failure"
    assert row.last_update_error == "boom"
    assert row.auto_update_enabled == false
  end

  test "cancels when service is already running" do
    start_compose(fn _cmd, _args -> {"unreachable", 0} end)

    Repo.get_by!(Service, name: "photon")
    |> Service.changeset(%{last_update_status: "running"})
    |> Repo.update!()

    assert {:cancel, :already_running} = perform_job(UpdateService, %{"name" => "photon"})
  end

  test "cancels when service not found" do
    start_compose(fn _cmd, _args -> {"unreachable", 0} end)

    assert {:cancel, :service_not_found} =
             perform_job(UpdateService, %{"name" => "ghost"})
  end
end
