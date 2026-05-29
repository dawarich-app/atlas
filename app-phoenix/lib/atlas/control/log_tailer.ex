defmodule Atlas.Control.LogTailer do
  @moduledoc """
  Tails `docker compose logs -f <name>` and forwards every line to:

    * `Atlas.Control.ServiceState.feed/2` so the parser updates its state, and
    * `Atlas.PubSub` topic `logs:<name>` for any LiveView watching raw log
      output.

  The executable resolution is configurable so tests can substitute `cat`
  (reading from a fixture file) or any other line-emitting program.
  """

  use GenServer

  alias Phoenix.PubSub

  @line_max_bytes 8192

  def start_link(opts) when is_list(opts), do: GenServer.start_link(__MODULE__, opts)
  def start_link(name) when is_binary(name), do: start_link(name: name)

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    executable = Keyword.get(opts, :executable) || System.find_executable("docker")
    args = Keyword.get(opts, :args, ["compose", "logs", "-f", "--tail=0", name])

    if is_nil(executable) do
      {:stop, :no_executable}
    else
      port =
        Port.open(
          {:spawn_executable, executable},
          [:binary, :exit_status, {:line, @line_max_bytes}, args: args]
        )

      {:ok, %{port: port, name: name}}
    end
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port, name: name} = state) do
    Atlas.Control.ServiceState.feed(name, line)
    PubSub.broadcast(Atlas.PubSub, "logs:#{name}", {:log_line, line})
    {:noreply, state}
  end

  def handle_info({port, {:data, {:noeol, _partial}}}, %{port: port} = state) do
    # Drop oversize fragments rather than buffering — log lines longer than
    # 8 KiB don't carry useful parser signal.
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, _code}}, %{port: port} = state) do
    {:stop, :normal, state}
  end
end
