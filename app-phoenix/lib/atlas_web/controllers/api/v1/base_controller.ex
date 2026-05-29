defmodule AtlasWeb.Api.V1.BaseController do
  defmacro __using__(_) do
    quote do
      use AtlasWeb, :controller
      use OpenApiSpex.ControllerSpecs

      import AtlasWeb.Api.V1.BaseController,
        only: [
          clamp_int: 4,
          parse_float: 1,
          parse_bbox: 1,
          parse_latlon: 1,
          require_param: 2,
          meta: 1,
          meta: 2
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

  def meta(conn, extra \\ %{}) do
    request_id =
      conn
      |> Plug.Conn.get_req_header("x-request-id")
      |> List.first()

    Map.merge(%{request_id: request_id}, Map.new(extra))
  end
end
