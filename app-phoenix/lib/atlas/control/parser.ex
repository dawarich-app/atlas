defmodule Atlas.Control.Parser do
  @moduledoc """
  Behaviour for upstream-service log parsers. Each parser implementation maintains
  its own accumulator state and emits a normalized result per fed log line.

  Parsers are pure modules — no GenServer state, no side effects. Ported from the
  Go `atlas-control` sidecar (`internal/parsers/*.go`).
  """

  @type result :: %{
          phase: String.t() | nil,
          progress: float() | nil,
          last_log_line: String.t() | nil,
          ready: boolean()
        }

  @callback init() :: term()
  @callback feed(line :: String.t(), acc :: term()) :: {result, new_acc :: term()}
end
