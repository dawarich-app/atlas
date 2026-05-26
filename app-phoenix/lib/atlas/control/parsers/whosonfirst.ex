defmodule Atlas.Control.Parsers.Whosonfirst do
  @moduledoc """
  Parses whosonfirst download logs through downloading → complete.

  Ported from `atlas/atlas-control/internal/parsers/whosonfirst.go`.
  """

  @behaviour Atlas.Control.Parser

  @download_re ~r/Downloading whosonfirst/
  @complete_re ~r/Download complete/

  @impl true
  def init,
    do: %{phase: nil, progress: nil, ready: false, last_log_line: nil}

  @impl true
  def feed(line, acc) do
    acc = %{acc | last_log_line: line}

    new_acc =
      cond do
        Regex.match?(@complete_re, line) ->
          %{acc | phase: "complete", ready: true, progress: 1.0}

        Regex.match?(@download_re, line) ->
          %{acc | phase: "downloading", progress: 0.3}

        true ->
          acc
      end

    {new_acc, new_acc}
  end
end
