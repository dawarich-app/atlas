defmodule Atlas.Control.LogTailer do
  @moduledoc """
  Tails `docker compose logs -f <name>` and forwards every line to:

    * `Atlas.Control.ServiceState.feed/2` so the parser updates its state, and
    * `Atlas.PubSub` topic `logs:<name>` for any LiveView watching raw log
      output.

  The executable resolution is configurable so tests can substitute `cat`
  (reading from a fixture file) or any other line-emitting program.
  """

  # Transient: a finished log stream (port exited, EOF broadcast) must stay
  # down until the next explicit start_tail — a permanent restart would spawn
  # `docker compose logs` in a tight loop when the CLI is broken.
  use GenServer, restart: :transient

  alias Phoenix.PubSub

  @line_max_bytes 8192

  def start_link(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: Atlas.Control.Registry.via({:tailer, name}))
  end

  def start_link(name) when is_binary(name), do: start_link(name: name)

  @max_recent_lines 500

  @doc """
  Lines buffered by the running tailer (oldest first, capped at
  #{@max_recent_lines}) — lets a viewer opened after boot see history the
  tailer already consumed. `[]` when no tailer runs for `name`.
  """
  def recent(name) do
    GenServer.call(Atlas.Control.Registry.via({:tailer, name}), :recent)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc """
  Default docker invocation: follow with 200 lines of history so a viewer
  opened after a failure still sees what happened. `--project-directory`
  matches `Atlas.Control.DockerCompose` so the tailer addresses the same
  compose project the host uses.
  """
  def default_args(name) do
    ["compose"] ++ project_dir_args() ++ ["logs", "-f", "--tail=200", name]
  end

  defp project_dir_args do
    case System.get_env("HOST_PROJECT_DIR") do
      nil -> []
      "" -> []
      dir -> ["--project-directory", dir]
    end
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    executable = Keyword.get(opts, :executable) || System.find_executable("docker")
    args = Keyword.get(opts, :args, default_args(name))

    if is_nil(executable) do
      {:stop, :no_executable}
    else
      port =
        Port.open(
          {:spawn_executable, executable},
          [:binary, :exit_status, {:line, @line_max_bytes}, args: args]
        )

      {:ok, %{port: port, name: name, recent: []}}
    end
  end

  @impl true
  def handle_call(:recent, _from, state) do
    {:reply, Enum.reverse(state.recent), state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port, name: name} = state) do
    safe_feed(name, line)
    PubSub.broadcast(Atlas.PubSub, "logs:#{name}", {:log_line, line})
    {:noreply, %{state | recent: Enum.take([line | state.recent], @max_recent_lines)}}
  end

  def handle_info({port, {:data, {:noeol, _partial}}}, %{port: port} = state) do
    # Drop oversize fragments rather than buffering — log lines longer than
    # 8 KiB don't carry useful parser signal.
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port, name: name} = state) do
    # Tell viewers the stream ended (instead of leaving a silently frozen
    # panel) before this process goes away.
    PubSub.broadcast(Atlas.PubSub, "logs:#{name}", {:log_eof, code})
    {:stop, :normal, state}
  end

  # A missing ServiceState actor must not take the log stream down with it.
  defp safe_feed(name, line) do
    Atlas.Control.ServiceState.feed(name, line)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end
end
