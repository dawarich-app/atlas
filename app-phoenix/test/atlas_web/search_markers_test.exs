defmodule AtlasWeb.SearchMarkersTest do
  use ExUnit.Case, async: true

  alias AtlasWeb.SearchMarkers

  defp place(overrides \\ %{}) do
    Map.merge(
      %{
        id: "N:1",
        label: "McDonald's, Berlin, Deutschland",
        type: "fast_food",
        coords: %{lat: 52.5, lon: 13.4},
        address: %{street: "Alexanderplatz", house_number: "7", postcode: "10178", city: "Berlin"},
        admin: %{city: "Berlin", country: "Deutschland"}
      },
      overrides
    )
  end

  describe "points/1" do
    test "carries what a popup needs, not just a label" do
      [p] = SearchMarkers.points([place()])

      assert p.label == "McDonald's, Berlin, Deutschland"
      assert p.category == "Fast food"
      assert p.address == "Alexanderplatz 7, 10178 Berlin"
      assert p.lat == 52.5
      assert p.lon == 13.4
    end

    test "builds the address from whichever parts exist" do
      assert [%{address: "Alexanderplatz, Berlin"}] =
               SearchMarkers.points([
                 place(%{address: %{street: "Alexanderplatz", city: "Berlin"}})
               ])

      assert [%{address: "10178 Berlin"}] =
               SearchMarkers.points([place(%{address: %{postcode: "10178", city: "Berlin"}})])
    end

    test "an absent address is nil rather than an empty string" do
      # The popup decides whether to render the row at all, so it must be able
      # to tell "no address" from "an address that happens to be blank".
      assert [%{address: nil}] = SearchMarkers.points([place(%{address: %{}})])
      assert [%{address: nil}] = SearchMarkers.points([place(%{address: nil})])
    end

    test "skips places with no usable coordinates" do
      # Photon occasionally returns a feature with an empty geometry; a marker
      # at [nil, nil] throws inside MapLibre and takes the whole list with it.
      assert SearchMarkers.points([place(%{coords: %{lat: nil, lon: nil}})]) == []
      assert SearchMarkers.points([place(%{coords: %{}})]) == []
    end

    test "keeps the good places when one is unusable" do
      points = SearchMarkers.points([place(%{coords: %{}}), place(%{id: "N:2"})])

      assert [%{id: "N:2"}] = points
    end

    test "an unknown type still yields a category rather than nothing" do
      assert [%{category: "Result"}] = SearchMarkers.points([place(%{type: nil})])
    end
  end

  describe "osm_url" do
    test "expands Photon's single-letter osm_type into an OSM permalink" do
      # Place.id is "N:240109189"; openstreetmap.org wants /node/240109189.
      # Passing the raw id through, as the Rails popup did, yields a 404.
      assert [%{osm_url: "https://www.openstreetmap.org/node/1"}] =
               SearchMarkers.points([place(%{id: "N:1"})])

      assert [%{osm_url: "https://www.openstreetmap.org/way/22"}] =
               SearchMarkers.points([place(%{id: "W:22"})])

      assert [%{osm_url: "https://www.openstreetmap.org/relation/333"}] =
               SearchMarkers.points([place(%{id: "R:333"})])
    end

    test "an id that names no OSM object yields no link" do
      # Better a popup without a link than one that 404s.
      for id <- ["", "1", "X:1", "N:", nil] do
        assert [%{osm_url: nil}] = SearchMarkers.points([place(%{id: id})]),
               "expected nil for #{inspect(id)}"
      end
    end
  end

  describe "region" do
    test "names the wider area when the address does not already" do
      assert [%{region: "Bayern, Deutschland"}] =
               SearchMarkers.points([
                 place(%{
                   admin: %{state: "Bayern", country: "Deutschland"},
                   address: %{city: "München"}
                 })
               ])
    end

    test "is nil when there is nothing beyond the address to add" do
      assert [%{region: nil}] = SearchMarkers.points([place(%{admin: %{}})])
      assert [%{region: nil}] = SearchMarkers.points([place(%{admin: nil})])
    end
  end
end
