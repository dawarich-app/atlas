defmodule Atlas.Control.ApplyLog do
  @moduledoc """
  Log of the region apply pipeline — the applier's own steps plus osmium's
  output — for the stages that run inside this container and so have no
  `docker compose logs` of their own.

  Lines go out on `topic/0` as `{:log_line, line}`, the same message a
  service's `logs:<name>` topic carries, so the service log modal renders it
  unchanged. Cleared when an apply starts.
  """

  use GenServer

  @topic "logs:apply"
  @max_lines 500

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def topic, do: @topic

  def append(line), do: GenServer.cast(__MODULE__, {:append, line})

  def clear, do: GenServer.cast(__MODULE__, :clear)

  @doc "Buffered lines, oldest first."
  def recent, do: GenServer.call(__MODULE__, :recent)

  @impl true
  def init(_opts), do: {:ok, []}

  @impl true
  def handle_cast({:append, line}, lines) do
    line = "#{Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")} #{line}"
    Phoenix.PubSub.broadcast(Atlas.PubSub, @topic, {:log_line, line})
    {:noreply, Enum.take([line | lines], @max_lines)}
  end

  def handle_cast(:clear, _lines), do: {:noreply, []}

  @impl true
  def handle_call(:recent, _from, lines), do: {:reply, Enum.reverse(lines), lines}
end
