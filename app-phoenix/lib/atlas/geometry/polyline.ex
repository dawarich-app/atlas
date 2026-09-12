defmodule Atlas.Geometry.Polyline do
  @moduledoc """
  Google encoded polyline decoder.

  Implements the algorithm described at
  https://developers.google.com/maps/documentation/utilities/polylinealgorithm.

  Supports configurable precision:

    * `5` (default) — Google's standard encoding (1e5 scale factor)
    * `6` — Valhalla's `valhalla_encoded_polyline6` (1e6 scale factor)
  """

  import Bitwise

  @doc """
  Decode an encoded polyline string into a list of `{lat, lon}` tuples.

  Returns `[]` for an empty string.
  """
  @spec decode(String.t(), pos_integer()) :: [{float(), float()}]
  def decode(encoded, precision \\ 5)

  def decode("", _precision), do: []

  def decode(encoded, precision) when is_binary(encoded) and is_integer(precision) do
    factor = :math.pow(10, precision)

    do_decode(encoded, 0, 0, factor, [])
  end

  defp do_decode("", _lat, _lon, _factor, acc), do: Enum.reverse(acc)

  defp do_decode(rest, lat, lon, factor, acc) do
    {dlat, rest1} = decode_value(rest)
    {dlon, rest2} = decode_value(rest1)

    new_lat = lat + dlat
    new_lon = lon + dlon

    point = {new_lat / factor, new_lon / factor}

    do_decode(rest2, new_lat, new_lon, factor, [point | acc])
  end

  defp decode_value(str), do: decode_value(str, 0, 0)

  defp decode_value(<<char, rest::binary>>, shift, result) do
    b = char - 63
    new_result = bor(result, bsl(band(b, 0x1F), shift))

    if b < 0x20 do
      value =
        if band(new_result, 1) == 1 do
          -bsr(new_result, 1) - 1
        else
          bsr(new_result, 1)
        end

      {value, rest}
    else
      decode_value(rest, shift + 5, new_result)
    end
  end

  @doc """
  Encode `{lat, lon}` tuples with Google encoded-polyline encoding.

  Precision 6 is used when Atlas splits a Valhalla map match into multiple
  independently drawable segments.
  """
  @spec encode([{number(), number()}], pos_integer()) :: String.t()
  def encode(points, precision \\ 5) when is_list(points) and is_integer(precision) do
    factor = :math.pow(10, precision)

    {encoded, _lat, _lon} =
      Enum.reduce(points, {[], 0, 0}, fn {lat, lon}, {acc, previous_lat, previous_lon} ->
        latitude = round(lat * factor)
        longitude = round(lon * factor)

        {[acc, encode_value(latitude - previous_lat), encode_value(longitude - previous_lon)],
         latitude, longitude}
      end)

    IO.iodata_to_binary(encoded)
  end

  defp encode_value(delta) do
    delta
    |> then(fn value -> if value < 0, do: bnot(bsl(value, 1)), else: bsl(value, 1) end)
    |> encode_chunks([])
  end

  defp encode_chunks(value, acc) when value >= 0x20 do
    encode_chunks(bsr(value, 5), [bor(0x20, band(value, 0x1F)) + 63 | acc])
  end

  defp encode_chunks(value, acc) do
    acc
    |> Enum.reverse([value + 63])
    |> List.to_string()
  end
end
