defmodule Atlas.Control.LogTailer.Supervisor do
  @moduledoc """
  DynamicSupervisor for `Atlas.Control.LogTailer` Port wrappers.

  One tailer per service. Restarted on crash; on clean exit (docker process
  exits 0) the child stays down until the next `start_tail/1`.
  """

  use DynamicSupervisor

  alias Atlas.Control.LogTailer

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Spawn a tailer for `name`; opts are forwarded to `LogTailer.start_link/1`."
  def start_tail(name) when is_binary(name) do
    DynamicSupervisor.start_child(__MODULE__, {LogTailer, name: name})
  end

  def start_tail(opts) when is_list(opts) do
    DynamicSupervisor.start_child(__MODULE__, {LogTailer, opts})
  end
end
