defmodule AtlasWeb.Api.V1.BaseController do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  defmacro __using__(_) do
    quote do
      use AtlasWeb, :controller
      use OpenApiSpex.ControllerSpecs

      import AtlasWeb.Api.V1.BaseController,
        only: [
          clamp_int: 4,
          parse_float: 1,
          parse_float_required: 1,
          parse_bbox: 1,
          parse_bbox_required: 1,
          parse_latlon: 1,
          require_param: 2,
          meta: 1,
          meta: 2,
          error: 4,
          error: 5,
          missing_param: 2,
          validation_error: 2,
          validation_error: 3
        ]
    end
  end

  def clamp_int(value, default, min_v, max_v) do
    case value do
      nil ->
        default

      "" ->
        default

      v when is_binary(v) ->
        case Integer.parse(v) do
          {n, _} -> n |> max(min_v) |> min(max_v)
          :error -> default
        end

      v when is_integer(v) ->
        v |> max(min_v) |> min(max_v)

      _ ->
        default
    end
  end

  def parse_float(nil), do: nil
  def parse_float(""), do: nil

  def parse_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> nil
    end
  end

  def parse_float(v) when is_number(v), do: v * 1.0

  def parse_float_required(value) do
    case parse_float(value) do
      nil -> {:error, :invalid_float}
      f -> {:ok, f}
    end
  end

  def parse_bbox(nil), do: nil

  def parse_bbox(v) when is_binary(v) do
    case String.split(v, ",") do
      [w, s, e, n] ->
        parsed = Enum.map([w, s, e, n], &parse_float/1)
        if Enum.any?(parsed, &is_nil/1), do: nil, else: parsed

      _ ->
        nil
    end
  end

  def parse_bbox_required(value) do
    case parse_bbox(value) do
      nil -> {:error, :invalid_bbox}
      bbox -> {:ok, bbox}
    end
  end

  def parse_latlon(nil), do: :error
  def parse_latlon(""), do: :error

  def parse_latlon(str) when is_binary(str) do
    case String.split(str, ",") do
      [lat, lon] ->
        case {parse_float(lat), parse_float(lon)} do
          {lat_f, lon_f} when is_number(lat_f) and is_number(lon_f) ->
            {:ok, %{lat: lat_f, lon: lon_f}}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  def parse_latlon(_), do: :error

  def require_param(conn, param) do
    case conn.params[param] do
      nil -> {:error, :missing}
      "" -> {:error, :missing}
      v -> {:ok, v}
    end
  end

  def meta(_conn, extra \\ %{}) do
    base = %{timestamp: DateTime.utc_now() |> DateTime.to_iso8601()}
    Map.merge(base, Map.new(extra))
  end

  @doc """
  Render a structured error response with optional details.

  Body shape:
      {"error": {"code": ..., "message": ..., "details": {...}}}

  `details` is omitted when empty to match Rails behavior.
  """
  def error(conn, status, code, message, details \\ %{}) do
    conn
    |> put_status(status)
    |> json(%{error: build_error(code, message, details)})
  end

  @doc """
  400 Bad Request response for a missing required parameter.

  Matches Rails `ActionController::ParameterMissing` semantics.
  """
  def missing_param(conn, param) do
    error(conn, :bad_request, "MISSING_PARAM", "#{param} is required", %{param: to_string(param)})
  end

  @doc """
  422 Unprocessable Entity response for a semantically invalid request
  (bad bbox, non-numeric lat/lon, unknown enum, etc.).
  """
  def validation_error(conn, message, details \\ %{}) do
    error(conn, :unprocessable_entity, "VALIDATION_ERROR", message, details)
  end

  defp build_error(code, message, details) when is_map(details) and map_size(details) == 0,
    do: %{code: code, message: message}

  defp build_error(code, message, details),
    do: %{code: code, message: message, details: details}
end
