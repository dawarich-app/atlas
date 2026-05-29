defmodule Atlas.Control.DockerCompose do
  @moduledoc """
  Serializes `docker compose` invocations through a single GenServer.

  All callers go through `GenServer.call/3`, so only one `docker compose`
  process runs at a time. In production, the runner is `System.cmd/3`; tests
  pass an injected runner (`runner:` option to `start_link/1`) that captures
  arguments and returns canned output.

  Mirrors the behavior of the Go sidecar's `internal/dockerexec/dockerexec.go`.
  """

  use GenServer

  @type runner :: (String.t(), [String.t()] -> {Collectable.t(), exit_status :: non_neg_integer()})

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Run `docker compose up -d <name>`."
  def start(name), do: call(["up", "-d", name], :timer.minutes(10))

  @doc "Run `docker compose stop <name>`."
  def stop(name), do: call(["stop", name], :timer.minutes(2))

  @doc "Run `docker compose logs --tail=<tail> <name>`."
  def logs(name, tail \\ 200), do: call(["logs", "--tail=#{tail}", name])

  @doc "Run `docker compose pull <name>` to update the image."
  def update(name, _kind), do: call(["pull", name], :timer.minutes(15))

  defp call(args, timeout \\ :timer.minutes(2)) do
    GenServer.call(__MODULE__, {:compose, args}, timeout)
  end

  @impl true
  def init(opts) do
    runner = Keyword.get(opts, :runner, &System.cmd/2)
    {:ok, %{runner: runner}}
  end

  @impl true
  def handle_call({:compose, args}, _from, %{runner: runner} = state) do
    {output, exit_code} = runner.("docker", ["compose" | args])
    {:reply, {exit_code, output}, state}
  end
end
