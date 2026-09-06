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

  require Logger

  import Ecto.Query
  alias Atlas.Control.{Service, ServiceState}
  alias Atlas.{Repo, Settings}

  def select_transit(name) when name in ~w(otp motis),
    do: GenServer.call(__MODULE__, {:select_transit, name}, :timer.minutes(15))

  def enforce_transit_selection,
    do: GenServer.call(__MODULE__, :enforce_transit, :timer.minutes(3))

  @type runner :: (String.t(), [String.t()] ->
                     {Collectable.t(), exit_status :: non_neg_integer()})
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

    # `--project-directory` is a HOST path, so compose looks for the project's
    # .env somewhere this container cannot see and every service silently comes
    # up on compose defaults instead of the operator's settings. compose.yml
    # bind-mounts the project root at /work, so point --env-file there.
    env_file = Keyword.get(opts, :env_file, default_env_file())

    unless is_nil(env_file) or readable_file?(env_file) do
      Logger.info(
        "no readable #{env_file}; control-plane services will use compose defaults. " <>
          "Settings from the project .env (region, UID/GID, heap) will not apply."
      )
    end

    {:ok, %{runner: runner, project_dir: project_dir, env_file: env_file}}
  end

  @impl true
  def handle_call({:select_transit, name}, _from, state) do
    other = other_transit(name)

    result =
      with {:ok, _} <- run(state, ["stop", other]),
           {:ok, output} <- run(state, ["ps", "-q", "--status", "running", other]),
           :ok <- stopped(output) do
        {:ok, _} =
          Repo.transaction(fn ->
            Repo.update_all(from(s in Service, where: s.name in ["otp", "motis"]),
              set: [enabled: false]
            )

            {:ok, _} = Settings.set("transit_backend", name)
            Repo.update_all(from(s in Service, where: s.name == ^name), set: [enabled: true])
          end)

        sync_transit(other, false, :ok)
        sync_transit(name, true, :ok)
        result = run(state, ["up", "-d", name])
        sync_transit(name, true, result)
        result
      end

    {:reply, result, state}
  end

  def handle_call(:enforce_transit, _from, state) do
    other = other_transit(Settings.transit_backend())
    Repo.update_all(from(s in Service, where: s.name == ^other), set: [enabled: false])
    result = run(state, ["stop", other])
    sync_transit(other, false, result)
    {:reply, result, state}
  end

  def handle_call({:compose, [op | rest] = args}, _from, state) when op in ["up", "restart"] do
    name = List.last(rest)

    reply =
      if name in ~w(otp motis), do: start_selected(state, name, args), else: run(state, args)

    {:reply, reply, state}
  end

  def handle_call({:compose, args}, _from, state), do: {:reply, run(state, args), state}

  defp start_selected(state, name, args) do
    if name == Settings.transit_backend() do
      with {:ok, _} <- run(state, ["stop", other_transit(name)]),
           {:ok, output} <- run(state, ["ps", "-q", "--status", "running", other_transit(name)]),
           :ok <- stopped(output) do
        run(state, args)
      end
    else
      {:error, 1, "#{name} is not the selected transit engine"}
    end
  end

  defp run(state, args) do
    full_args = ["compose"] ++ project_args(state) ++ env_file_args(state) ++ args

    case state.runner.("docker", full_args) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, code, output}
    end
  end

  defp other_transit("otp"), do: "motis"
  defp other_transit("motis"), do: "otp"

  defp stopped(output) do
    if String.trim(output) == "",
      do: :ok,
      else: {:error, 1, "Previous transit engine is still running"}
  end

  defp sync_transit(name, enabled, result) do
    ServiceState.transit_state(name, enabled, result)
  end

  @doc """
  Container-local path to the project `.env`, i.e. the project root as this
  container sees it (`.:/work:ro` in compose.yml) rather than the host path in
  `--project-directory`. Override with `ATLAS_ENV_FILE`.
  """
  def default_env_file do
    case System.get_env("ATLAS_ENV_FILE") do
      nil -> "/work/.env"
      "" -> "/work/.env"
      path -> path
    end
  end

  @doc """
  `--env-file` arguments for the default project `.env`, or `[]` when there
  isn't a readable one. Shared with `Atlas.Control.LogTailer` so every compose
  subcommand interpolates the compose file the same way.
  """
  def default_env_file_args, do: env_file_args(%{env_file: default_env_file()})

  defp project_args(%{project_dir: nil}), do: []
  defp project_args(%{project_dir: dir}), do: ["--project-directory", dir]

  # Only pass the flag when compose can actually read the file: it errors out on
  # a missing --env-file, and .env is optional. Readability matters as much as
  # existence — an unreadable file would turn a silent fallback into a hard stop.
  defp env_file_args(%{env_file: file}) when is_binary(file) do
    if readable_file?(file), do: ["--env-file", file], else: []
  end

  defp env_file_args(_state), do: []

  defp readable_file?(path) do
    File.regular?(path) and match?({:ok, _}, File.open(path, [:read], & &1))
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
