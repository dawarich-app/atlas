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
end
