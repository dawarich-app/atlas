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

  test "restart rejects an empty Compose project instead of claiming success" do
    start_compose({"", 0})
    assert {:error, 1, message} = DockerCompose.restart("motis")
    assert message =~ "HOST_PROJECT_DIR"
    assert_received {:stub, "docker", ["compose", "ps", "-a", "-q", "motis"]}
    refute_received {:stub, "docker", ["compose", "restart", "motis"]}
  end

  test "restart propagates container lookup errors without attempting restart" do
    start_compose({"daemon unavailable", 1})
    assert {:error, 1, "daemon unavailable"} = DockerCompose.restart("motis")
    refute_received {:stub, "docker", ["compose", "restart", "motis"]}
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

  describe "project .env" do
    setup do
      dir = Path.join(System.tmp_dir!(), "compose-env-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    defp start_with(opts) do
      test_pid = self()
      runner = fn cmd, args -> send(test_pid, {:stub, cmd, args}) && {"ok", 0} end
      start_supervised!({DockerCompose, [runner: runner] ++ opts})
    end

    test "passes --env-file so services inherit the operator's .env", %{dir: dir} do
      env_file = Path.join(dir, ".env")
      File.write!(env_file, "COUNTRY_CODE=nl\n")

      start_with(project_dir: "/srv/atlas", env_file: env_file)

      assert {:ok, "ok"} = DockerCompose.start("photon")

      assert_received {:stub, "docker", args}

      assert args == [
               "compose",
               "--project-directory",
               "/srv/atlas",
               "--env-file",
               env_file,
               "up",
               "-d",
               "photon"
             ]
    end

    test "omits --env-file when the project has no .env", %{dir: dir} do
      start_with(project_dir: "/srv/atlas", env_file: Path.join(dir, ".env"))

      assert {:ok, "ok"} = DockerCompose.start("photon")

      assert_received {:stub, "docker", args}
      refute "--env-file" in args
      assert args == ["compose", "--project-directory", "/srv/atlas", "up", "-d", "photon"]
    end

    test "an unreadable .env is skipped rather than passed to compose", %{dir: dir} do
      env_file = Path.join(dir, ".env")
      File.write!(env_file, "COUNTRY_CODE=nl\n")
      File.chmod!(env_file, 0o000)
      on_exit(fn -> File.chmod(env_file, 0o600) end)

      start_with(project_dir: "/srv/atlas", env_file: env_file)

      assert {:ok, "ok"} = DockerCompose.start("photon")

      assert_received {:stub, "docker", args}

      refute "--env-file" in args,
             "compose cannot read the file either, so passing it turns a silent fallback into a hard failure"
    end

    test "ATLAS_ENV_FILE set to empty is treated as unset" do
      System.put_env("ATLAS_ENV_FILE", "")
      on_exit(fn -> System.delete_env("ATLAS_ENV_FILE") end)

      assert DockerCompose.default_env_file() == "/work/.env"
    end

    test "defaults to the container-local mount of the project root", %{dir: dir} do
      env_file = Path.join(dir, ".env")
      File.write!(env_file, "COUNTRY_CODE=nl\n")

      # /work is where compose.yml bind-mounts the project root (`.:/work:ro`),
      # so the .env the operator edited is readable from inside the container
      # even though --project-directory names a host path.
      assert DockerCompose.default_env_file() == "/work/.env"

      start_with(project_dir: "/srv/atlas", env_file: env_file)
      assert {:ok, "ok"} = DockerCompose.start("photon")
      assert_received {:stub, "docker", args}
      assert "--env-file" in args
    end
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
