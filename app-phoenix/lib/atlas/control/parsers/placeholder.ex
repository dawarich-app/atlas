defmodule Atlas.Control.Parsers.Placeholder do
  @moduledoc """
  Parses Placeholder log output through extract → build → optimize → ready phases.

  Ported from `atlas/atlas-control/internal/parsers/placeholder.go`.
  """

  @behaviour Atlas.Control.Parser

  @extract_re ~r/Creating extract at/
  @build_re ~r/populate fts/
  @optimize_re ~r/optimize\.\.\./
  @listening_re ~r/\[placeholder\].*listening on/
  @request_re ~r/\[placeholder\].*GET \//

  @impl true
  def init,
    do: %{phase: nil, progress: nil, ready: false, last_log_line: nil}

  @impl true
  def feed(line, acc) do
    acc = %{acc | last_log_line: line}

    new_acc =
      cond do
        Regex.match?(@listening_re, line) or Regex.match?(@request_re, line) ->
          %{acc | phase: "ready", ready: true, progress: 1.0}

        Regex.match?(@optimize_re, line) ->
          %{acc | phase: "optimizing", progress: 0.9}

        Regex.match?(@build_re, line) ->
          %{acc | phase: "building", progress: 0.6}

        Regex.match?(@extract_re, line) ->
          %{acc | phase: "extracting", progress: 0.2}

        true ->
          acc
      end

    {new_acc, new_acc}
  end
end
