defmodule AtlasWeb.Api.V1.MapMatchController do
  @moduledoc """
  `POST /api/v1/map-match` — snap a recorded GPS trace onto the road network.

  A POST rather than a GET like `/route`: a trace is thousands of points, far
  past what a query string can carry.
  """

  use AtlasWeb.Api.V1.BaseController
  action_fallback AtlasWeb.Api.V1.FallbackController

  alias Atlas.Maps.MapMatch
  alias Atlas.Maps.Upstream.Valhalla
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [response: 3]

  @formats ~w(polyline6 geojson)
  @trace_option_params ~w(search_radius gps_accuracy breakage_distance)a

  operation(:create,
    summary: "Map-match a recorded GPS trace onto the road network",
    description: """
    Takes the points you actually recorded and returns every matched road
    segment plus a correlation result for each input point. `shape` is an array
    of `{lat, lon}` objects, optionally carrying `time` (epoch seconds) and
    `accuracy` (metres) — supplying both materially improves the match.

    Set `format` to `geojson` to get decoded `LineString` or `MultiLineString`
    geometry instead of encoded polyline segments. Set `include_directions`
    only when narrative directions are needed; it performs a second Valhalla
    request and preserves every returned directions path.
    """,
    request_body:
      {"Map match request", "application/json",
       %OpenApiSpex.Schema{
         type: :object,
         required: [:shape],
         properties: %{
           shape: %OpenApiSpex.Schema{
             type: :array,
             minItems: 2,
             description: "Recorded points, in order",
             items: %OpenApiSpex.Schema{
               type: :object,
               required: [:lat, :lon],
               properties: %{
                 lat: %OpenApiSpex.Schema{type: :number},
                 lon: %OpenApiSpex.Schema{type: :number},
                 time: %OpenApiSpex.Schema{type: :integer, description: "Epoch seconds"},
                 accuracy: %OpenApiSpex.Schema{type: :number, description: "Metres"}
               }
             }
           },
           mode: %OpenApiSpex.Schema{type: :string, enum: Valhalla.modes()},
           shape_match: %OpenApiSpex.Schema{type: :string, enum: Valhalla.shape_matches()},
           format: %OpenApiSpex.Schema{type: :string, enum: @formats},
           include_directions: %OpenApiSpex.Schema{type: :boolean, default: false},
           search_radius: %OpenApiSpex.Schema{type: :number},
           gps_accuracy: %OpenApiSpex.Schema{type: :number},
           breakage_distance: %OpenApiSpex.Schema{type: :number}
         }
       }, required: true},
    responses: %{
      200 => response("Matched trace", "application/json", Schemas.Response),
      400 => response("Missing shape", "application/json", Schemas.Error),
      429 => response("Map matching capacity reached", "application/json", Schemas.Error),
      422 => response("Invalid or unmatchable trace", "application/json", Schemas.Error),
      502 => response("Upstream error", "application/json", Schemas.Error),
      503 => response("Upstream unavailable", "application/json", Schemas.Error)
    }
  )

  def create(conn, %{"shape" => raw_shape} = params) when is_list(raw_shape) do
    with {:ok, shape} <- parse_shape(raw_shape),
         {:ok, mode} <- parse_enum(params["mode"], Valhalla.modes(), "mode", "auto"),
         {:ok, shape_match} <-
           parse_enum(params["shape_match"], Valhalla.shape_matches(), "shape_match", "map_snap"),
         {:ok, format} <- parse_enum(params["format"], @formats, "format", "polyline6"),
         {:ok, include_directions} <-
           parse_boolean(params["include_directions"], "include_directions", false),
         {:ok, result} <-
           MapMatch.match(
             shape: shape,
             mode: mode,
             shape_match: shape_match,
             format: format,
             include_directions: include_directions,
             trace_options: trace_options(params)
           ) do
      json(conn, %{
        data: result.features,
        meta:
          meta(conn, %{
            mode: mode,
            shape_match: shape_match,
            format: format,
            include_directions: include_directions,
            points: length(shape),
            max_points: MapMatch.max_points()
          })
      })
    end
  end

  def create(_conn, _params), do: {:error, :missing, "shape"}

  # Validated here rather than deeper down so the response can name the exact
  # index that failed: with a few thousand points, "a point is invalid" is not
  # an actionable error message.
  defp parse_shape(raw_shape) do
    raw_shape
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, &collect_point/2)
    |> finish_shape()
  end

  defp collect_point({raw, index}, {:ok, acc}) do
    case parse_point(raw) do
      {:ok, point} -> {:cont, {:ok, [point | acc]}}
      :error -> {:halt, invalid_point(index)}
    end
  end

  defp finish_shape({:ok, points}), do: {:ok, Enum.reverse(points)}
  defp finish_shape(error), do: error

  defp invalid_point(index) do
    {:error, :invalid, "shape[#{index}] must have numeric lat and lon",
     %{param: "shape", index: index}}
  end

  defp parse_point(%{"lat" => lat, "lon" => lon} = raw) do
    case {coordinate(lat), coordinate(lon)} do
      {lat_f, lon_f} when is_float(lat_f) and is_float(lon_f) ->
        {:ok,
         %{
           lat: lat_f,
           lon: lon_f,
           time: parse_number(raw["time"]),
           accuracy: parse_number(raw["accuracy"])
         }}

      _ ->
        :error
    end
  end

  defp parse_point(_raw), do: :error

  # Not `BaseController.parse_float/1`: it has no catch-all clause, so a JSON
  # `true` or `{}` raised FunctionClauseError and the client got a 500 for what
  # is plainly bad input. It is also lenient — `Float.parse("52,5")` yields
  # 52.0 and the point silently moves ~55 km — so trailing characters are
  # rejected here rather than dropped.
  defp coordinate(value) when is_number(value), do: value * 1.0

  defp coordinate(value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> nil
    end
  end

  defp coordinate(_value), do: nil

  defp trace_options(params) do
    Map.new(@trace_option_params, fn key ->
      {key, parse_number(params[Atom.to_string(key)])}
    end)
  end

  # Integers are preserved rather than coerced to floats: Valhalla's
  # `breakage_distance` and `time` are whole units, and a float there reads as
  # spurious precision in the request Atlas forwards.
  defp parse_number(value) when is_number(value), do: value

  defp parse_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> parse_float(value)
    end
  end

  defp parse_number(_value), do: nil

  defp parse_enum(value, allowed, name, default) do
    cond do
      value in [nil, ""] -> {:ok, default}
      is_binary(value) and value in allowed -> {:ok, value}
      true -> enum_error(allowed, name)
    end
  end

  defp enum_error(allowed, name) do
    {:error, :invalid, "#{name} must be one of #{Enum.join(allowed, ", ")}",
     %{param: name, allowed: allowed}}
  end

  defp parse_boolean(value, _name, default) when value in [nil, ""], do: {:ok, default}
  defp parse_boolean(value, _name, _default) when is_boolean(value), do: {:ok, value}
  defp parse_boolean("true", _name, _default), do: {:ok, true}
  defp parse_boolean("false", _name, _default), do: {:ok, false}

  defp parse_boolean(_value, name, _default) do
    {:error, :invalid, "#{name} must be true or false", %{param: name}}
  end
end
