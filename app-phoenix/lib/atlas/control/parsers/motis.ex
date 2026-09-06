defmodule Atlas.Control.Parsers.Motis do
  @moduledoc "Tracks MOTIS import and the server's actual listening signal."
  @behaviour Atlas.Control.Parser
  def init, do: %{phase: nil, progress: nil, ready: false, last_log_line: nil}

  def feed(line, acc) do
    acc = %{acc | last_log_line: line}

    acc =
      cond do
        String.contains?(line, "MOTIS ready") ->
          %{acc | phase: "ready", ready: true, progress: 1.0}

        String.contains?(line, "MOTIS importing") ->
          %{acc | phase: "building-graph", ready: false, progress: 0.1}

        String.contains?(line, "MOTIS error") ->
          %{acc | phase: "error", ready: false}

        true ->
          acc
      end

    {acc, acc}
  end
end
