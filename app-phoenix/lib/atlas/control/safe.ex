defmodule Atlas.Control.Safe do
  @moduledoc """
  Tolerant wrappers around `Atlas.Control.*` calls that may crash or exit
  (e.g. DockerCompose not running on this build, a ServiceState process
  that hasn't booted yet).

  Use these from LiveViews so a transient control-plane outage downgrades
  to a "—" placeholder instead of taking the page down.
  """

  alias Atlas.Control.ServiceState

  @doc """
  Best-effort `ServiceState.snapshot/1`. Returns `nil` if the registry has
  no process for `name`, or if the call exits/raises for any reason.
  """
  def snapshot(name) do
    ServiceState.snapshot(name)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Invoke `fun` and swallow any rescue/exit, returning `fallback` instead.
  Use when you need to call into a possibly-missing GenServer purely for
  the side effect and don't care about its return value.
  """
  def call(fun, fallback \\ :unavailable) when is_function(fun, 0) do
    fun.()
  rescue
    _ -> fallback
  catch
    :exit, _ -> fallback
  end
end
