defmodule Atlas.Control.Registry do
  @moduledoc """
  Process registry for `Atlas.Control.ServiceState` GenServers.

  Address with `{:via, Registry, {Atlas.Control.Registry, service_name}}`.

  The Registry itself is started by the supervision tree under this module name;
  this module just exposes the `via/1` helper for callers.
  """

  @doc "Returns a via-tuple addressing the ServiceState registered for `name`."
  def via(name), do: {:via, Registry, {__MODULE__, name}}
end
