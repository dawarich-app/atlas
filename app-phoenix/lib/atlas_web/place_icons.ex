defmodule AtlasWeb.PlaceIcons do
  @moduledoc """
  Maps a `Atlas.Maps.Place` `:type` onto a Lucide icon and a human category
  label, so a result list distinguishes a street from a station at a glance.

  Keyed on `Place.type`, which is Photon's `osm_value` falling back to
  `osm_key`. Ported from the Rails Atlas `search_controller.js` `TYPE_ICONS`,
  with one substitution: that map used `navigation` for streets, which this
  repo's `priv/icons` does not carry — `route` does, and reads the same.

  Photon emits far more `osm_value`s than this table covers. An unmapped type
  keeps the generic pin but surfaces the raw value as its label, which still
  tells the reader more than a bare pin.
  """

  @table %{
    "house" => {"map-pin", "Address"},
    "street" => {"route", "Street"},
    "city" => {"landmark", "City"},
    "district" => {"landmark", "District"},
    "locality" => {"landmark", "Locality"},
    "county" => {"landmark", "County"},
    "state" => {"landmark", "Region"},
    "country" => {"landmark", "Country"},
    "attraction" => {"map-pin", "Attraction"},
    "amenity" => {"map-pin", "POI"},
    "shop" => {"store", "Shop"},
    "supermarket" => {"shopping-cart", "Supermarket"},
    "restaurant" => {"utensils", "Restaurant"},
    "hotel" => {"bed", "Hotel"},
    "tourism" => {"map-pin", "Tourism"},
    "leisure" => {"trees", "Leisure"},
    "park" => {"trees", "Park"},
    "station" => {"train-front", "Station"},
    "aerodrome" => {"plane", "Airport"},
    "airport" => {"plane", "Airport"}
  }

  @fallback_icon "map-pin"

  @doc "The `{icon, label}` pair for a place type."
  @spec for(String.t() | nil) :: {String.t(), String.t()}
  def for(type) when is_binary(type) and type != "" do
    Map.get_lazy(@table, type, fn -> {@fallback_icon, humanize(type)} end)
  end

  def for(_), do: {@fallback_icon, "Result"}

  # Photon hands back osm_values verbatim, so an unmapped one reached the UI as
  # `fast_food` — and rendered `FAST_FOOD` once the row's uppercase styling hit
  # it. Rails humanised the underscores for exactly this reason.
  defp humanize(type) do
    type |> String.replace("_", " ") |> String.capitalize()
  end

  @doc "The full type table, for tests and any surface that wants a legend."
  @spec table() :: %{optional(String.t()) => {String.t(), String.t()}}
  def table, do: @table
end
