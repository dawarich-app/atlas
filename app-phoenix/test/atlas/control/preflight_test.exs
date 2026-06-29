defmodule Atlas.Control.PreflightTest do
  use ExUnit.Case, async: false

  alias Atlas.Control.Preflight

  setup do
    tmp = Path.join(System.tmp_dir!(), "preflight-#{System.unique_integer([:positive])}")
    for d <- ~w(osm gtfs otp tiles), do: File.mkdir_p!(Path.join(tmp, d))

    on_exit(fn ->
      File.rm_rf!(tmp)
      Preflight.clear()
    end)

    {:ok, tmp: tmp}
  end

  defp ok_runner("docker", ["compose" | _]), do: {"v5.1.4\n", 0}
  defp ok_runner("docker", ["ps" | _]), do: {"", 0}

  test "all green when docker, compose, socket and dirs are usable", %{tmp: tmp} do
    results =
      Preflight.run(
        runner: &ok_runner/2,
        data_dir: tmp,
        find_executable: fn _bin -> "/usr/bin/stub" end
      )

    assert Enum.all?(results, &(&1.status == :ok))
    assert Preflight.healthy?(results)
  end

  test "missing compose plugin is reported with a rebuild remedy", %{tmp: tmp} do
    runner = fn
      "docker", ["compose" | _] -> {"docker: 'compose' is not a docker command", 1}
      "docker", ["ps" | _] -> {"", 0}
    end

    results =
      Preflight.run(
        runner: runner,
        data_dir: tmp,
        find_executable: fn _bin -> "/usr/bin/stub" end
      )

    refute Preflight.healthy?(results)
    compose = Enum.find(results, &(&1.check == :compose))
    assert compose.status == :error
    assert compose.detail =~ "not a docker command"
    assert compose.remedy =~ "image"
  end

  test "socket permission failure points at DOCKER_GID", %{tmp: tmp} do
    runner = fn
      "docker", ["compose" | _] -> {"v5.1.4\n", 0}
      "docker", ["ps" | _] -> {"permission denied while trying to connect to the Docker daemon socket", 1}
    end

    results =
      Preflight.run(
        runner: runner,
        data_dir: tmp,
        find_executable: fn _bin -> "/usr/bin/stub" end
      )

    socket = Enum.find(results, &(&1.check == :socket))
    assert socket.status == :error
    assert socket.remedy =~ "DOCKER_GID"
  end

  test "unwritable data dir is reported", %{tmp: tmp} do
    File.rm_rf!(Path.join(tmp, "gtfs"))

    results =
      Preflight.run(
        runner: &ok_runner/2,
        data_dir: tmp,
        find_executable: fn _bin -> "/usr/bin/stub" end
      )

    dirs = Enum.find(results, &(&1.check == :data_dirs))
    assert dirs.status == :error
    assert dirs.detail =~ "gtfs"
  end

  test "refresh/1 caches results for results/0", %{tmp: tmp} do
    results =
      Preflight.refresh(
        runner: &ok_runner/2,
        data_dir: tmp,
        find_executable: fn _bin -> "/usr/bin/stub" end
      )

    assert Preflight.results() == results
  end
end
