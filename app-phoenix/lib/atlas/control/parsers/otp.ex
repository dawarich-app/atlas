defmodule Atlas.Control.Parsers.OTP do
  @moduledoc """
  Parses OpenTripPlanner logs across OSM load → street-graph build → GTFS load →
  trip-patterns → graph save → ready (with error detection).

  That order is OTP's, not the intuitive one: it finishes the street graph
  before it reads a single GTFS entity. `priv/parser_fixtures/otp-full-build.log`
  is an unedited capture of one container start, and the phase-order test in
  `otp_test.exs` asserts the sequence against it.

  Ported from `atlas/atlas-control/internal/parsers/otp.go`.
  """

  @behaviour Atlas.Control.Parser

  @osm_re ~r/Loaded OSM|Parse OSM Ways|Parse OSM Nodes/
  @gtfs_re ~r/Loaded GTFS|Reading entity: org\.onebusaway/
  @street_graph_re ~r/Build street graph progress: ([\d,]+) of ([\d,]+) \((\d+)%\)/
  @trip_patterns_re ~r/build trip patterns|GenerateTripPatternsOperation/
  @graph_re ~r/Graph built|Graph saved|HierarchyBuilder/
  # Captured from the pinned image, not paraphrased: OTP says "Started listener
  # bound to", never "Started listening", and "Grizzly server running", never
  # "Grizzly server started". The earlier patterns matched no line OTP has ever
  # emitted, so the service sat at saving-graph 90% until someone happened to
  # call the API and @serve_re rescued it. priv/parser_fixtures/otp-ready.log is
  # real output — recapture it there if a version bump changes the wording.
  @ready_re ~r/is ready for routing|Grizzly server running|Started listener bound to/
  @serve_re ~r{GET /otp/}
  @error_re ~r/Parameter error|java\.lang\.OutOfMemoryError|Exception in thread/

  @impl true
  def init,
    do: %{phase: nil, progress: nil, ready: false, last_log_line: nil}

  @impl true
  def feed(line, acc) do
    acc = %{acc | last_log_line: line}

    new_acc =
      cond do
        serving?(line) ->
          %{acc | phase: "ready", ready: true, progress: 1.0}

        Regex.match?(@error_re, line) ->
          %{acc | phase: "error", ready: false}

        match = Regex.run(@street_graph_re, line) ->
          %{acc | phase: "building-graph", progress: graph_progress(match, acc.progress)}

        Regex.match?(@trip_patterns_re, line) ->
          %{acc | phase: "trip-patterns", progress: max_progress(acc.progress, 0.7)}

        Regex.match?(@graph_re, line) ->
          %{acc | phase: "saving-graph", progress: max_progress(acc.progress, 0.9)}

        Regex.match?(@gtfs_re, line) ->
          %{acc | phase: "loading-gtfs", progress: max_progress(acc.progress, 0.5)}

        Regex.match?(@osm_re, line) ->
          %{acc | phase: "loading-osm", progress: max_progress(acc.progress, 0.2)}

        true ->
          acc
      end

    {new_acc, new_acc}
  end

  defp serving?(line), do: Regex.match?(@ready_re, line) or Regex.match?(@serve_re, line)

  defp graph_progress([_, _of, _total, pct_str], fallback) do
    case Integer.parse(pct_str) do
      {pct, _} -> 0.3 + pct / 100.0 * 0.5
      :error -> fallback
    end
  end

  defp max_progress(nil, floor), do: floor
  defp max_progress(current, floor) when current < floor, do: floor
  defp max_progress(current, _floor), do: current
end
