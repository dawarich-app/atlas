defmodule Atlas.Control.DockerCompose do
  @moduledoc """
  Serializes `docker compose` invocations through a single GenServer.

  All callers go through `GenServer.call/3`, so only one `docker compose`
  process runs at a time. In production, the runner is `System.cmd/3`; tests
  pass an injected runner (`runner:` option to `start_link/1`) that captures
  arguments and returns canned output.

  Every command returns `{:ok, output}` on exit 0 and `{:error, exit_code,
  output}` otherwise — callers must not discard failures.
  """

  use GenServer

  @type runner :: (String.t(), [String.t()] -> {Collectable.t(), exit_status :: non_neg_integer()})
  @type result :: {:ok, String.t()} | {:error, non_neg_integer(), String.t()}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Run `docker compose up -d <name>`."
  @spec start(String.t()) :: result
  def start(name), do: call(["up", "-d", name], :timer.minutes(10))

  @doc "Run `docker compose stop <name>`."
  @spec stop(String.t()) :: result
  def stop(name), do: call(["stop", name], :timer.minutes(2))

  @doc "Run `docker compose restart <name>`."
  @spec restart(String.t()) :: result
  def restart(name), do: call(["restart", name], :timer.minutes(5))

  @doc "Run `docker compose logs --tail=<tail> <name>`."
  @spec logs(String.t(), non_neg_integer()) :: result
  def logs(name, tail \\ 200), do: call(["logs", "--tail=#{tail}", name])

  @doc "True when the service has a running container (`compose ps -q --status running`)."
  @spec running?(String.t()) :: {:ok, boolean()} | {:error, non_neg_integer(), String.t()}
  def running?(name) do
    case call(["ps", "-q", "--status", "running", name], :timer.seconds(30)) do
      {:ok, output} -> {:ok, String.trim(output) != ""}
      {:error, _code, _output} = error -> error
    end
  end

  @doc "Run `docker compose pull <name>` to update the image."
  @spec update(String.t(), atom()) :: result
  def update(name, _kind), do: call(["pull", name], :timer.minutes(15))

  @doc """
  Probe whether the docker CLI, the compose plugin, and the daemon socket are
  all usable. Returns `{:ok, version}` or `{:error, detail}` — the preflight
  check renders the detail to the operator.
  """
  @spec available?() :: {:ok, String.t()} | {:error, String.t()}
  def available? do
    case call(["version", "--short"], :timer.seconds(15)) do
      {:ok, version} -> {:ok, String.trim(version)}
      {:error, _code, output} -> {:error, String.trim(output)}
    end
  catch
    :exit, reason -> {:error, "docker compose probe failed: #{inspect(reason)}"}
  end

  defp call(args, timeout \\ :timer.minutes(2)) do
    GenServer.call(__MODULE__, {:compose, args}, timeout)
  end

  @impl true
  def init(opts) do
    runner = Keyword.get(opts, :runner, &default_runner/2)

    # Relative bind paths in the compose file (./data/photon etc.) must
    # resolve against the HOST checkout, not this container's /work mount —
    # the daemon only knows host paths. Mirrors the Go sidecar's
    # `--project-directory` handling.
    project_dir = Keyword.get(opts, :project_dir, host_project_dir())

    {:ok, %{runner: runner, project_dir: project_dir}}
  end

  @impl true
  def handle_call({:compose, args}, _from, %{runner: runner} = state) do
    full_args =
      case state.project_dir do
        nil -> ["compose" | args]
        dir -> ["compose", "--project-directory", dir | args]
      end

    reply =
      case runner.("docker", full_args) do
        {output, 0} -> {:ok, output}
        {output, code} -> {:error, code, output}
      end

    {:reply, reply, state}
  end

  defp host_project_dir do
    case System.get_env("HOST_PROJECT_DIR") do
      nil -> nil
      "" -> nil
      dir -> dir
    end
  end

  defp default_runner(cmd, args), do: System.cmd(cmd, args, stderr_to_stdout: true)
end
