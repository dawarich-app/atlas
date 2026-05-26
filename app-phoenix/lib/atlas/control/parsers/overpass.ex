defmodule Atlas.Control.Parsers.Overpass do
  @moduledoc """
  Parses Overpass API logs through download → ingest → ready (and error) phases.

  Ported from `atlas/atlas-control/internal/parsers/overpass.go`.
  """

  @behaviour Atlas.Control.Parser

  @download_re ~r/Downloading planet/
  @ingest_re ~r/compiled \d+ blocks/
  @error_re ~r/Failed to process planet file|bzip2 error|Parse error at/
  @ready_re ~r/Server started|fcgiwrap.*listening|nginx.*ready/
  @serve_re ~r{GET /api/}

  @impl true
  def init,
    do: %{phase: nil, progress: nil, ready: false, last_log_line: nil}

  @impl true
  def feed(line, acc) do
    acc = %{acc | last_log_line: line}

    new_acc =
      cond do
        Regex.match?(@ready_re, line) or Regex.match?(@serve_re, line) ->
          %{acc | phase: "ready", ready: true, progress: 1.0}

        Regex.match?(@error_re, line) ->
          %{acc | phase: "error", ready: false}

        Regex.match?(@ingest_re, line) ->
          %{acc | phase: "ingesting", progress: 0.6}

        Regex.match?(@download_re, line) ->
          %{acc | phase: "downloading", progress: 0.2}

        true ->
          acc
      end

    {new_acc, new_acc}
  end
end
