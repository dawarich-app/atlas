defmodule Atlas.Control.Parsers.Libpostal do
  @moduledoc """
  Parses libpostal service logs to detect the ready signal.

  Ported from `atlas/atlas-control/internal/parsers/libpostal.go`.
  """

  @behaviour Atlas.Control.Parser

  @ready_re ~r/STATUS listening on/

  @impl true
  def init,
    do: %{phase: nil, progress: nil, ready: false, last_log_line: nil}

  @impl true
  def feed(line, acc) do
    acc = %{acc | last_log_line: line}

    new_acc =
      if Regex.match?(@ready_re, line) do
        %{acc | phase: "ready", ready: true, progress: 1.0}
      else
        acc
      end

    {new_acc, new_acc}
  end
end
