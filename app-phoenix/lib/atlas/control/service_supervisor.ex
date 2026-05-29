defmodule Atlas.Control.ServiceSupervisor do
  @moduledoc """
  DynamicSupervisor for the per-service `Atlas.Control.ServiceState` actors.

  Children are addressed via `Atlas.Control.Registry`, so duplicate starts
  return `{:error, {:already_started, pid}}` — which `start_service/3`
  surfaces unchanged so callers can decide whether to ignore it.
  """

  use DynamicSupervisor

  alias Atlas.Control.ServiceState

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Start a ServiceState child for `name` with the given `profile` and `parser_mod`."
  def start_service(name, profile, parser_mod) do
    DynamicSupervisor.start_child(__MODULE__, {ServiceState, {name, profile, parser_mod}})
  end
end
