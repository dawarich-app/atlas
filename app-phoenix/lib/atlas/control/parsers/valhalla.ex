defmodule Atlas.Control.Parsers.Valhalla do
  @moduledoc """
  Parses Valhalla routing tile-build logs across parsing → admins → elevation →
  tiles → ready phases.

  Ported from `atlas/atlas-control/internal/parsers/valhalla.go`.
  """

  @behaviour Atlas.Control.Parser

  @parse_re ~r/Parsing relations/
  @admins_re ~r/Building admin db/
  @elevation_re ~r/downloading SRTM|Adding elevation/
  @tiles_re ~r/building tiles|Running valhalla_build_tiles/
  @progress_re ~r/Build street graph progress: ([\d,]+) of ([\d,]+) \((\d+)%\)/
  @tiles_ready_re ~r/Tile build complete|Tile extract successfully loaded/
  @serve_re ~r{valhalla_service|GET / HTTP|HTTP/[\d.]+\s+200}

  @impl true
  def init,
    do: %{phase: nil, progress: nil, ready: false, last_log_line: nil}

  @impl true
  def feed(line, acc) do
    acc = %{acc | last_log_line: line}

    new_acc =
      cond do
        Regex.match?(@tiles_ready_re, line) or Regex.match?(@serve_re, line) ->
          %{acc | phase: "ready", ready: true, progress: 1.0}

        match = Regex.run(@progress_re, line) ->
          [_, _of, _total, pct_str] = match

          progress =
            case Integer.parse(pct_str) do
              {pct, _} -> pct / 100.0
              :error -> acc.progress
            end

          %{acc | phase: "building-tiles", progress: progress}

        Regex.match?(@tiles_re, line) ->
          %{acc | phase: "building-tiles", progress: max_progress(acc.progress, 0.5)}

        Regex.match?(@elevation_re, line) ->
          %{acc | phase: "building-elevation", progress: max_progress(acc.progress, 0.4)}

        Regex.match?(@admins_re, line) ->
          %{acc | phase: "building-admins", progress: max_progress(acc.progress, 0.3)}

        Regex.match?(@parse_re, line) ->
          %{acc | phase: "parsing", progress: max_progress(acc.progress, 0.1)}

        true ->
          acc
      end

    {new_acc, new_acc}
  end

  defp max_progress(nil, floor), do: floor
  defp max_progress(current, floor) when current < floor, do: floor
  defp max_progress(current, _floor), do: current
end
