defmodule Atlas.Maps.MapMatch do
  @moduledoc """
  Snap a recorded GPS trace onto the road network via Valhalla's Meili
  matcher (`/trace_attributes`).

  This is the inverse of `Atlas.Maps.Route`: routing invents a path between
  two points, matching takes a path you already walked and decides which edges
  you were actually on.

  `/trace_attributes` is used instead of `/trace_route` because it returns a
  correlation for every input point. Valhalla may split a noisy trace into
  several paths; Atlas preserves those paths instead of silently returning
  only the first one.

  Two output shapes, chosen with `:format`:

    * `"polyline6"` (default) — one encoded `shape` per matched segment.
    * `"geojson"` — a `LineString` for one segment or a `MultiLineString`
      when the matcher reports discontinuities.

  Set `:include_directions` to make an additional `/trace_route` request and
  include every directions path, including Valhalla's `alternates`.
  """

  alias Atlas.Geometry.Polyline
  alias Atlas.Maps.{Result, Upstream.Client, Upstream.Valhalla}

  require Logger

  @min_points 2
  @max_points 10_000
  @polyline_precision 6

  # Only used when Valhalla's own explanation is missing or unreadable.
  @generic_rejection "the trace could not be matched to the road network — it may lie " <>
                       "outside the loaded region, or the points may be too sparse or too noisy"

  @doc """
  Upper bound on trace length, overridable with `MAP_MATCH_MAX_POINTS`.

  Matching is superlinear in point count and holds a Valhalla worker for the
  whole request, so an unbounded trace is a denial-of-service on a shared
  instance.
  """
  def max_points, do: Client.env_int("MAP_MATCH_MAX_POINTS", @max_points)

  @doc "Smallest trace that can be matched."
  def min_points, do: @min_points

  @doc """
  Match `:shape` — a list of `%{lat:, lon:}` maps, optionally with `:time`
  and `:accuracy` — onto the road network.

  Returns `{:ok, %Result{}}`, or one of the error tuples
  `AtlasWeb.Api.V1.FallbackController` knows how to render.
  """
  def match(opts) do
    shape = opts[:shape] || []

    with :ok <- validate_shape(shape),
         {:ok, attributes} <- request_attributes(shape, opts),
         {:ok, directions} <- request_directions(shape, opts) do
      {:ok, build_result(attributes, opts[:format], directions)}
    end
  end

  defp validate_shape(shape) do
    count = length(shape)
    max = max_points()

    cond do
      count < @min_points ->
        {:error, :invalid, "shape must have at least #{@min_points} points",
         %{param: "shape", min: @min_points}}

      count > max ->
        {:error, :too_many, max}

      true ->
        :ok
    end
  end

  defp request_attributes(shape, opts) do
    Valhalla.trace_attributes(trace_request(shape, opts))
    |> handle_response()
  end

  defp request_directions(shape, opts) do
    if opts[:include_directions] do
      Valhalla.trace_route(trace_request(shape, opts))
      |> handle_response()
      |> case do
        {:ok, body} -> {:ok, direction_paths(body)}
        error -> error
      end
    else
      {:ok, nil}
    end
  end

  defp trace_request(shape, opts) do
    [
      shape: shape,
      mode: opts[:mode] || "auto",
      shape_match: opts[:shape_match],
      trace_options: opts[:trace_options]
    ]
  end

  # Every Valhalla 400 is the caller's input being unusable, so 422 is right
  # across the board — 502 would send the operator debugging a service that is
  # behaving correctly. But the REASON varies: unmatchable geometry
  # (error_code 171), a trace longer than `max_distance` (200 km by default —
  # one day of driving), more points than `max_shape`, an out-of-range trace
  # option. Relay Valhalla's own message instead of asserting one of them.
  defp handle_response({:ok, body}), do: {:ok, body}

  defp handle_response({:error, %Client.BadResponse{status: 400, body: body}}) do
    Logger.warning("valhalla rejected the trace: #{inspect(body)}")
    {:error, :invalid, upstream_message(body), upstream_details(body)}
  end

  defp handle_response({:error, %Client.Unavailable{} = error}) do
    Logger.warning("valhalla unavailable: #{Exception.message(error)}")
    {:error, error}
  end

  defp handle_response({:error, %Client.BadResponse{} = error}) do
    Logger.warning("valhalla bad response: #{Exception.message(error)}")
    {:error, error}
  end

  defp upstream_message(%{"error" => error}) when is_binary(error) and error != "", do: error
  defp upstream_message(_body), do: @generic_rejection

  defp upstream_details(%{"error_code" => code}) when is_integer(code),
    do: %{param: "shape", upstream_error_code: code}

  defp upstream_details(_body), do: %{param: "shape"}

  defp build_result(body, format, directions) do
    segments = matched_segments(body)

    common = %{
      summary: aggregate_summary(segments),
      matched_points: matched_points(body["matched_points"] || []),
      stats: match_stats(body, segments)
    }

    features =
      case format do
        "geojson" -> Map.merge(common, geojson_features(segments))
        _ -> Map.merge(common, polyline_features(segments))
      end
      |> maybe_put_directions(directions)

    %Result{features: features, upstream_status: "ok"}
  end

  # A reset in edge elapsed time marks the start of a new discontinuous path.
  # Valhalla serializes every path into one encoded shape, so drawing it as one
  # LineString creates false straight lines across unmatched gaps. Split at the
  # first shape index of every reset and keep each path independently drawable.
  defp matched_segments(body) do
    coordinates = Polyline.decode(body["shape"] || "", @polyline_precision)
    edges = body["edges"] || []

    case split_edges(edges) do
      [] when coordinates == [] -> []
      [] -> [%{coordinates: coordinates, summary: %{length: 0.0, time: 0.0}}]
      groups -> Enum.map(groups, &segment(&1, coordinates))
    end
    |> Enum.reject(&(length(&1.coordinates) < 2))
  end

  defp split_edges(edges) do
    {groups, current, _elapsed} =
      Enum.reduce(edges, {[], [], nil}, &split_edge/2)

    groups = if current == [], do: groups, else: [Enum.reverse(current) | groups]
    Enum.reverse(groups)
  end

  defp split_edge(edge, {groups, current, previous_elapsed}) do
    elapsed = get_in(edge, ["end_node", "elapsed_time"])

    if elapsed_reset?(current, previous_elapsed, elapsed) do
      {[Enum.reverse(current) | groups], [edge], elapsed}
    else
      next_elapsed = if is_number(elapsed), do: elapsed, else: previous_elapsed
      {groups, [edge | current], next_elapsed}
    end
  end

  defp elapsed_reset?(current, previous, elapsed) do
    current != [] and is_number(elapsed) and is_number(previous) and elapsed < previous
  end

  defp segment(edges, coordinates) do
    first = List.first(edges) || %{}
    last = List.last(edges) || %{}
    first_index = first["begin_shape_index"] || 0
    last_index = last["end_shape_index"] || first_index

    %{
      coordinates: Enum.slice(coordinates, first_index, last_index - first_index + 1),
      summary: %{
        length: edges |> Enum.reduce(0.0, &sum_edge_length/2) |> round_metric(),
        time: last |> get_in(["end_node", "elapsed_time"]) |> then(&(&1 || 0.0)) |> round_metric()
      }
    }
  end

  defp sum_edge_length(%{"length" => length}, total) when is_number(length), do: total + length
  defp sum_edge_length(_edge, total), do: total

  defp aggregate_summary(segments) do
    summary =
      Enum.reduce(segments, %{length: 0.0, time: 0.0}, fn segment, summary ->
        %{
          length: summary.length + segment.summary.length,
          time: summary.time + segment.summary.time
        }
      end)

    %{length: round_metric(summary.length), time: round_metric(summary.time)}
  end

  defp matched_points(points) do
    points
    |> Enum.with_index()
    |> Enum.map(fn {point, index} ->
      %{
        input_index: index,
        lat: point["lat"],
        lon: point["lon"],
        type: point["type"],
        edge_index: point["edge_index"],
        distance_along_edge: point["distance_along_edge"],
        distance_from_trace_point: point["distance_from_trace_point"]
      }
    end)
  end

  defp match_stats(body, segments) do
    points = body["matched_points"] || []
    frequencies = Enum.frequencies_by(points, &(&1["type"] || "unmatched"))

    distances =
      points
      |> Enum.map(& &1["distance_from_trace_point"])
      |> Enum.filter(&is_number/1)
      |> Enum.sort()

    %{
      matched: Map.get(frequencies, "matched", 0),
      interpolated: Map.get(frequencies, "interpolated", 0),
      unmatched: Map.get(frequencies, "unmatched", 0),
      segments: length(segments),
      mean_distance_from_trace_point: mean(distances),
      p95_distance_from_trace_point: percentile(distances, 0.95),
      max_distance_from_trace_point: List.last(distances),
      confidence_score: body["confidence_score"],
      raw_score: body["raw_score"]
    }
  end

  defp mean([]), do: nil
  defp mean(values), do: values |> Enum.sum() |> Kernel./(length(values)) |> round_metric()

  defp percentile([], _percentile), do: nil

  defp percentile(values, percentile) do
    index = max(ceil(length(values) * percentile) - 1, 0)
    Enum.at(values, index)
  end

  defp geojson_features(segments) do
    line_strings = Enum.map(segments, &geojson_coordinates(&1.coordinates))

    geometry =
      case line_strings do
        [coordinates] -> %{type: "LineString", coordinates: coordinates}
        coordinates -> %{type: "MultiLineString", coordinates: coordinates}
      end

    %{
      geometry: geometry,
      segments:
        Enum.map(segments, fn segment ->
          %{
            summary: segment.summary,
            geometry: %{type: "LineString", coordinates: geojson_coordinates(segment.coordinates)}
          }
        end),
      shape_format: "geojson"
    }
  end

  defp polyline_features(segments) do
    legs =
      Enum.map(segments, fn segment ->
        %{
          summary: segment.summary,
          shape: Polyline.encode(segment.coordinates, @polyline_precision)
        }
      end)

    %{legs: legs, shape_format: "valhalla_encoded_polyline6"}
  end

  defp geojson_coordinates(coordinates),
    do: Enum.map(coordinates, fn {lat, lon} -> [lon, lat] end)

  defp round_metric(value), do: Float.round(value * 1.0, 3)

  defp maybe_put_directions(features, nil), do: features
  defp maybe_put_directions(features, paths), do: Map.put(features, :directions, %{paths: paths})

  defp direction_paths(body) do
    [body["trip"] | body["alternates"] || []]
    |> Enum.map(fn
      %{"trip" => trip} -> trip
      trip -> trip
    end)
    |> Enum.filter(&is_map/1)
    |> Enum.map(&Map.take(&1, ["summary", "legs"]))
  end
end
