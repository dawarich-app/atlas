defmodule Atlas.Control.Preflight do
  @moduledoc """
  Boot-time control-plane diagnostics: docker CLI present, compose plugin
  usable, daemon socket reachable, data dirs writable, osmium installed.

  Failures surface as a banner in the Settings panel and `/admin` with a
  concrete remedy — a misconfigured `DOCKER_GID` must fail loudly at boot,
  not silently when the user clicks "Save & apply".

  `run/1` is pure (checks injected via opts for tests); `refresh/1` runs and
  caches in `:persistent_term` for `results/0`.
  """

  @key {__MODULE__, :results}
  @data_subdirs ~w(osm gtfs otp tiles)

  @type result :: %{check: atom(), status: :ok | :error, detail: String.t() | nil, remedy: String.t() | nil}

  @doc "Run all checks. Returns a list of result maps."
  def run(opts \\ []) do
    runner = Keyword.get(opts, :runner, &default_runner/2)
    data_dir = Keyword.get(opts, :data_dir, "/work/data")
    find_executable = Keyword.get(opts, :find_executable, &System.find_executable/1)

    [
      check_binary(:docker_cli, "docker", find_executable),
      check_compose(runner),
      check_socket(runner),
      check_data_dirs(data_dir),
      check_binary(:osmium, "osmium", find_executable)
    ]
  end

  @doc "Run all checks and cache the results for `results/0`."
  def refresh(opts \\ []) do
    results = run(opts)
    :persistent_term.put(@key, results)
    results
  end

  @doc """
  Last cached results — `[]` until the boot-time `refresh/1` lands. Render
  paths must never trigger docker probes themselves.
  """
  def results, do: :persistent_term.get(@key, [])

  @doc "Drop cached results (test isolation)."
  def clear, do: :persistent_term.erase(@key)

  @doc "True when every check passed."
  def healthy?(results) when is_list(results), do: Enum.all?(results, &(&1.status == :ok))

  @doc "Failed checks from a result list."
  def failures(results) when is_list(results), do: Enum.filter(results, &(&1.status == :error))

  defp check_binary(check, bin, find_executable) do
    case find_executable.(bin) do
      nil ->
        %{
          check: check,
          status: :error,
          detail: "`#{bin}` is not on PATH inside the app container",
          remedy: "Rebuild the app image — the release Dockerfile installs #{bin}."
        }

      _path ->
        %{check: check, status: :ok, detail: nil, remedy: nil}
    end
  end

  defp check_compose(runner) do
    case safe_run(runner, ["compose", "version", "--short"]) do
      {_out, 0} ->
        %{check: :compose, status: :ok, detail: nil, remedy: nil}

      {out, _code} ->
        %{
          check: :compose,
          status: :error,
          detail: String.trim(out),
          remedy:
            "The docker CLI has no compose v2 plugin. Rebuild the app image " <>
              "(the Dockerfile installs docker-ce-cli + docker-compose-plugin)."
        }
    end
  end

  defp check_socket(runner) do
    case safe_run(runner, ["ps", "--format", "{{.ID}}", "-n", "1"]) do
      {_out, 0} ->
        %{check: :socket, status: :ok, detail: nil, remedy: nil}

      {out, _code} ->
        %{
          check: :socket,
          status: :error,
          detail: String.trim(out),
          remedy:
            "Set DOCKER_GID to the docker socket's group and recreate the app " <>
              "container: Linux `stat -c %g /var/run/docker.sock` (often 999); " <>
              "macOS (OrbStack / Docker Desktop) `0`."
        }
    end
  end

  defp check_data_dirs(data_dir) do
    broken =
      Enum.reject(@data_subdirs, fn sub ->
        dir = Path.join(data_dir, sub)
        probe = Path.join(dir, ".preflight")

        File.dir?(dir) and
          match?(:ok, File.touch(probe)) and
          match?(:ok, File.rm(probe))
      end)

    if broken == [] do
      %{check: :data_dirs, status: :ok, detail: nil, remedy: nil}
    else
      %{
        check: :data_dirs,
        status: :error,
        detail: "not writable: #{Enum.join(broken, ", ")} (under #{data_dir})",
        remedy: "Check the compose volume mounts for ./data/* — region applies need them."
      }
    end
  end

  defp safe_run(runner, args) do
    runner.("docker", args)
  rescue
    e -> {Exception.message(e), 1}
  catch
    :exit, reason -> {"docker probe exited: #{inspect(reason)}", 1}
  end

  defp default_runner(cmd, args), do: System.cmd(cmd, args, stderr_to_stdout: true)
end
