defmodule Atlas.Maps.PlaceTest do
  use ExUnit.Case, async: true
  alias Atlas.Maps.Place

  @feature %{
    "geometry" => %{"coordinates" => [13.4, 52.5]},
    "properties" => %{
      "osm_type" => "W",
      "osm_id" => 42,
      "osm_key" => "tourism",
      "osm_value" => "attraction",
      "name" => "Brandenburger Tor",
      "housenumber" => "1",
      "street" => "Pariser Platz",
      "city" => "Berlin",
      "county" => "Mitte",
      "state" => "Berlin",
      "postcode" => "10117",
      "country" => "Germany",
      "countrycode" => "DE"
    }
  }

  test "from_photon_feature returns the canonical id/name/label/type/coords (parity fields)" do
    place = Place.from_photon_feature(@feature)
    assert place.id == "W:42"
    assert place.name == "Brandenburger Tor"
    assert place.label == "Brandenburger Tor, Berlin, Germany"
    assert place.type == "attraction"
    assert place.coords == %{lon: 13.4, lat: 52.5}
  end

  test "from_photon_feature keeps the legacy admin block unchanged (Rails parity)" do
    place = Place.from_photon_feature(@feature)

    assert place.admin == %{
             country: "Germany",
             state: "Berlin",
             county: "Mitte",
             city: "Berlin",
             postcode: "10117"
           }
  end

  test "from_photon_feature adds an enrichment-ready address block with house_number/street/countrycode" do
    place = Place.from_photon_feature(@feature)

    assert place.address == %{
             house_number: "1",
             street: "Pariser Platz",
             city: "Berlin",
             county: "Mitte",
             state: "Berlin",
             postcode: "10117",
             country: "Germany",
             countrycode: "DE"
           }
  end

  test "match_type is derived from the most precise present field; confidence is nil" do
    assert Place.from_photon_feature(@feature).match_type == "rooftop"
    assert Place.from_photon_feature(@feature).confidence == nil

    city_only = put_in(@feature["properties"], %{"name" => "Berlin", "city" => "Berlin"})
    assert Place.from_photon_feature(city_only).match_type == "locality"
  end

  test "from_photon_feature returns nil for a non-feature" do
    assert Place.from_photon_feature(%{"type" => "FeatureCollection"}) == nil
  end
end
