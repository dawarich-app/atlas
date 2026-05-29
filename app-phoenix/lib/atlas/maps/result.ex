defmodule Atlas.Maps.Result do
  defstruct features: [], upstream_status: "ok"

  @type upstream_status :: String.t()
  @type t :: %__MODULE__{features: term(), upstream_status: upstream_status}
end
