defmodule Atlas.Maps.MapMatchLimiter do
  @moduledoc """
  Fail-fast concurrency guard for Valhalla map matching.

  Atlas keeps no job queue here: up to the configured number of callers hold
  slots, and excess callers receive `{:error, :map_match_busy, limit}`. Caller
  processes are monitored so an abnormal exit cannot leak a slot.
  """

  use GenServer

  alias Atlas.Maps.Upstream.Client

  @default_limit 4

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    limit = Keyword.get(opts, :limit, configured_limit())
    start_opts = if name, do: [name: name], else: []

    GenServer.start_link(__MODULE__, max(limit, 1), start_opts)
  end

  @doc "Run a function while holding one matching slot, or fail immediately."
  def run(fun, server \\ __MODULE__) when is_function(fun, 0) do
    case checkout(server) do
      {:ok, token} ->
        try do
          fun.()
        after
          checkin(token, server)
        end

      busy ->
        busy
    end
  end

  @doc false
  def checkout(server \\ __MODULE__), do: GenServer.call(server, {:checkout, self()})

  @doc false
  def checkin(token, server \\ __MODULE__), do: GenServer.cast(server, {:checkin, token})

  @doc "Maximum number of map matches this limiter admits at once."
  def capacity(server \\ __MODULE__), do: GenServer.call(server, :capacity)

  defp configured_limit do
    Client.env_int("MAP_MATCH_CONCURRENCY", @default_limit)
  end

  @impl true
  def init(limit), do: {:ok, %{limit: limit, holders: %{}, monitors: %{}}}

  @impl true
  def handle_call({:checkout, pid}, _from, %{holders: holders, limit: limit} = state)
      when map_size(holders) < limit do
    token = make_ref()
    monitor = Process.monitor(pid)

    {:reply, {:ok, token},
     %{
       state
       | holders: Map.put(holders, token, monitor),
         monitors: Map.put(state.monitors, monitor, token)
     }}
  end

  def handle_call({:checkout, _pid}, _from, state) do
    {:reply, {:error, :map_match_busy, state.limit}, state}
  end

  def handle_call(:capacity, _from, state), do: {:reply, state.limit, state}

  @impl true
  def handle_cast({:checkin, token}, state), do: {:noreply, release(token, state)}

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, monitor) do
      {nil, _monitors} ->
        {:noreply, state}

      {token, monitors} ->
        {:noreply, %{state | holders: Map.delete(state.holders, token), monitors: monitors}}
    end
  end

  defp release(token, state) do
    case Map.pop(state.holders, token) do
      {nil, _holders} ->
        state

      {monitor, holders} ->
        Process.demonitor(monitor, [:flush])
        %{state | holders: holders, monitors: Map.delete(state.monitors, monitor)}
    end
  end
end
