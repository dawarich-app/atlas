defmodule Atlas.Maps.Place do
  @moduledoc """
  Canonical place shape shared by every geocoding endpoint (Search, Reverse,
  Geocode). One normalizer, one shape.

  Fields:
    * `id/name/label/type/coords/admin` — legacy parity fields (do not change).
    * `address` — enrichment-ready block (house_number, street, ...). SP3
      (OpenAddresses/GeoNames) fills the gaps here without a contract change.
    * `match_type` — derived precision tier (rooftop|street|locality|region|country|unknown).
    * `confidence` — reserved for SP3; always `nil` today.
  """

  @spec from_photon_feature(map()) :: map() | nil
  def from_photon_feature(%{"properties" => props, "geometry" => geom}) do
    coords = Map.get(geom, "coordinates", [])
    [lon, lat | _] = coords ++ [nil, nil]

    %{
      id: osm_id(props),
      name: props["name"],
      label: label(props),
      type: props["osm_value"] || props["osm_key"],
      coords: %{lon: lon, lat: lat},
      admin: admin(props),
      address: address(props),
      match_type: match_type(props),
      confidence: nil
    }
  end

  def from_photon_feature(_), do: nil

  defp osm_id(props),
    do: [props["osm_type"], props["osm_id"]] |> Enum.reject(&is_nil/1) |> Enum.join(":")

  defp label(props),
    do:
      [props["name"], props["city"], props["state"], props["country"]]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.join(", ")

  defp admin(props) do
    %{
      country: props["country"],
      state: props["state"],
      county: props["county"],
      city: props["city"],
      postcode: props["postcode"]
    }
    |> drop_nils()
  end

  defp address(props) do
    %{
      house_number: props["housenumber"],
      street: props["street"],
      city: props["city"],
      county: props["county"],
      state: props["state"],
      postcode: props["postcode"],
      country: props["country"],
      countrycode: props["countrycode"]
    }
    |> drop_nils()
  end

  defp match_type(props) do
    cond do
      props["housenumber"] -> "rooftop"
      props["street"] -> "street"
      props["city"] -> "locality"
      props["state"] -> "region"
      props["country"] -> "country"
      true -> "unknown"
    end
  end

  defp drop_nils(map),
    do: map |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()
end
