defmodule Atlas.Geometry.Coord do
  @moduledoc """
  Pure helpers around the `"lat,lon"` string convention used by the LV
  form inputs and the Routing endpoint, plus polyline → GeoJSON
  conversion for rendering route legs on the map.
  """

  alias Atlas.Geometry.Polyline

  @doc """
  Parse a `"lat,lon"` (or `"  lat , lon "`) string into `{:ok, %{lat:, lon:}}`.
  Returns `:error` on any malformed input.
  """
  def parse_latlon(str) when is_binary(str) do
    parts = str |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    with [lat_s, lon_s] <- parts,
         {lat, ""} <- Float.parse(lat_s),
         {lon, ""} <- Float.parse(lon_s) do
      {:ok, %{lat: lat, lon: lon}}
    else
      _ -> :error
    end
  end

  def parse_latlon(_), do: :error

  @doc """
  Format a numeric coordinate (lat or lon) as a fixed 6-decimal string,
  matching the convention used by Atlas form fields.
  """
  def format(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 6)
  def format(value) when is_integer(value), do: Integer.to_string(value)
  def format(value) when is_binary(value), do: value

  @doc """
  Convert a list of route `legs` (each with an encoded `shape` polyline) into a
  GeoJSON FeatureCollection of `LineString` features.

  Handles both Valhalla legs (string keys, `valhalla_encoded_polyline6`) and
  transit legs from OTP (atom keys, `google_polyline5`); the polyline precision
  is taken from each leg's `shape_format`, defaulting to 6.

  Empty/missing shapes are dropped.
  """
  def legs_to_geojson(legs) when is_list(legs) do
    features =
      Enum.flat_map(legs, fn leg ->
        case leg_field(leg, :shape) do
          shape when is_binary(shape) and shape != "" ->
            coords =
              shape
              |> Polyline.decode(precision_for(leg_field(leg, :shape_format)))
              |> Enum.map(fn {lat, lon} -> [lon, lat] end)

            [
              %{
                type: "Feature",
                geometry: %{type: "LineString", coordinates: coords},
                properties: %{}
              }
            ]

          _ ->
            []
        end
      end)

    %{type: "FeatureCollection", features: features}
  end

  def legs_to_geojson(_), do: %{type: "FeatureCollection", features: []}

  # Legs come from two sources with different key styles: Valhalla legs are
  # string-keyed, OTP transit legs are atom-keyed. Read either.
  defp leg_field(leg, key) when is_map(leg) do
    Map.get(leg, key) || Map.get(leg, Atom.to_string(key))
  end

  defp leg_field(_, _), do: nil

  defp precision_for("google_polyline5"), do: 5
  defp precision_for("valhalla_encoded_polyline6"), do: 6
  defp precision_for(_), do: 6
end
