defmodule Atlas.Control.DockerComposeTest do
  use ExUnit.Case, async: false
  alias Atlas.Control.DockerCompose

  defp start_compose(result \\ {"ok", 0}) do
    test_pid = self()

    runner = fn cmd, args ->
      send(test_pid, {:stub, cmd, args})
      result
    end

    start_supervised!({DockerCompose, runner: runner})
  end

  test "start/1 invokes `docker compose up -d <name>`" do
    start_compose()
    assert {:ok, "ok"} = DockerCompose.start("photon")
    assert_received {:stub, "docker", ["compose", "up", "-d", "photon"]}
  end

  test "stop/1 invokes `docker compose stop <name>`" do
    start_compose()
    assert {:ok, "ok"} = DockerCompose.stop("photon")
    assert_received {:stub, "docker", ["compose", "stop", "photon"]}
  end

  test "restart/1 invokes `docker compose restart <name>`" do
    start_compose()
    assert {:ok, "ok"} = DockerCompose.restart("valhalla")
    assert_received {:stub, "docker", ["compose", "restart", "valhalla"]}
  end

  test "logs/2 invokes `docker compose logs --tail=<n> <name>`" do
    start_compose()
    assert {:ok, "ok"} = DockerCompose.logs("photon", 50)
    assert_received {:stub, "docker", ["compose", "logs", "--tail=50", "photon"]}
  end

  test "logs/1 defaults tail to 200" do
    start_compose()
    assert {:ok, "ok"} = DockerCompose.logs("photon")
    assert_received {:stub, "docker", ["compose", "logs", "--tail=200", "photon"]}
  end

  test "update/2 invokes `docker compose pull <name>`" do
    start_compose()
    assert {:ok, "ok"} = DockerCompose.update("photon", :image)
    assert_received {:stub, "docker", ["compose", "pull", "photon"]}
  end

  test "non-zero exit returns error with code and output" do
    start_compose({"'compose' is not a docker command", 1})

    assert {:error, 1, "'compose' is not a docker command"} = DockerCompose.start("photon")
  end

  test "project_dir resolves sidecar bind paths against the host project dir" do
    test_pid = self()

    runner = fn cmd, args ->
      send(test_pid, {:stub, cmd, args})
      {"ok", 0}
    end

    start_supervised!({DockerCompose, runner: runner, project_dir: "/srv/atlas"})

    assert {:ok, "ok"} = DockerCompose.start("photon")

    assert_received {:stub, "docker",
                     ["compose", "--project-directory", "/srv/atlas", "up", "-d", "photon"]}
  end

  test "running?/1 is true when `compose ps` lists a running container" do
    start_compose({"3f2a1b\n", 0})

    assert {:ok, true} = DockerCompose.running?("photon")
    assert_received {:stub, "docker", ["compose", "ps", "-q", "--status", "running", "photon"]}
  end

  test "running?/1 is false when `compose ps` output is empty" do
    start_compose({"\n", 0})

    assert {:ok, false} = DockerCompose.running?("photon")
  end

  test "running?/1 propagates errors" do
    start_compose({"permission denied", 1})

    assert {:error, 1, "permission denied"} = DockerCompose.running?("photon")
  end

  test "available?/0 probes `docker compose version`" do
    start_compose({"v5.1.4\n", 0})

    assert {:ok, "v5.1.4"} = DockerCompose.available?()
    assert_received {:stub, "docker", ["compose", "version", "--short"]}
  end

  test "available?/0 returns error detail on failure" do
    start_compose({"permission denied on socket", 1})

    assert {:error, "permission denied on socket"} = DockerCompose.available?()
  end
end
