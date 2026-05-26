defmodule Atlas.Control.DockerComposeTest do
  use ExUnit.Case, async: false
  alias Atlas.Control.DockerCompose

  setup do
    test_pid = self()
    runner = fn cmd, args ->
      send(test_pid, {:stub, cmd, args})
      {"ok", 0}
    end

    {:ok, pid} = start_supervised({DockerCompose, runner: runner})
    {:ok, pid: pid}
  end

  test "start/1 invokes `docker compose up -d <name>`" do
    assert {0, "ok"} = DockerCompose.start("photon")
    assert_received {:stub, "docker", ["compose", "up", "-d", "photon"]}
  end

  test "stop/1 invokes `docker compose stop <name>`" do
    assert {0, "ok"} = DockerCompose.stop("photon")
    assert_received {:stub, "docker", ["compose", "stop", "photon"]}
  end

  test "logs/2 invokes `docker compose logs --tail=<n> <name>`" do
    assert {0, "ok"} = DockerCompose.logs("photon", 50)
    assert_received {:stub, "docker", ["compose", "logs", "--tail=50", "photon"]}
  end

  test "logs/1 defaults tail to 200" do
    assert {0, "ok"} = DockerCompose.logs("photon")
    assert_received {:stub, "docker", ["compose", "logs", "--tail=200", "photon"]}
  end

  test "update/2 invokes `docker compose pull <name>`" do
    assert {0, "ok"} = DockerCompose.update("photon", :image)
    assert_received {:stub, "docker", ["compose", "pull", "photon"]}
  end
end
