defmodule Atlas.Control.Parsers.Photon do
  @moduledoc """
  Parses Photon geocoder log output to detect download, extraction, and ready phases.

  Ported from `atlas/atlas-control/internal/parsers/photon.go`.
  """

  @behaviour Atlas.Control.Parser

  @download_start_re ~r/Starting download/
  @progress_re ~r/Download progress: ([\d.]+)%/
  @extract_re ~r/Extracting|Download complete/
  @ready_re ~r/Photon ready after/

  @impl true
  def init,
    do: %{phase: nil, progress: nil, ready: false, last_log_line: nil}

  @impl true
  def feed(line, acc) do
    acc = %{acc | last_log_line: line}

    new_acc =
      cond do
        Regex.match?(@ready_re, line) ->
          %{acc | phase: "ready", ready: true, progress: 1.0}

        Regex.match?(@extract_re, line) ->
          %{acc | phase: "extracting"}

        match = Regex.run(@progress_re, line) ->
          [_, pct_str] = match

          progress =
            case Float.parse(String.trim(pct_str)) do
              {pct, _} -> pct / 100.0
              :error -> acc.progress
            end

          %{acc | phase: "downloading", progress: progress}

        Regex.match?(@download_start_re, line) ->
          %{acc | phase: "downloading"}

        true ->
          acc
      end

    {new_acc, new_acc}
  end
end
