defmodule AtlasWeb.PlaceIconsTest do
  use ExUnit.Case, async: true

  alias AtlasWeb.PlaceIcons

  describe "for/1" do
    test "maps Photon's granularity types to distinct icons" do
      assert {"landmark", "City"} = PlaceIcons.for("city")
      assert {"route", "Street"} = PlaceIcons.for("street")
      assert {"train-front", "Station"} = PlaceIcons.for("station")
      assert {"map-pin", "Address"} = PlaceIcons.for("house")
    end

    test "an unmapped type keeps the pin but shows the raw type as its label" do
      # Photon emits hundreds of osm_values. Naming the unmapped one still tells
      # the user more than a bare pin.
      assert {"map-pin", "Hairdresser"} = PlaceIcons.for("hairdresser")
      refute Map.has_key?(PlaceIcons.table(), "hairdresser")
    end

    test "an unmapped type reads as words, not as a raw OSM value" do
      # Photon returns osm_values verbatim, so the list was showing FAST_FOOD
      # once the label was uppercased by CSS. Rails humanised the underscores.
      assert {"map-pin", "Fast food"} = PlaceIcons.for("fast_food")
      assert {"map-pin", "Bus stop"} = PlaceIcons.for("bus_stop")
    end

    test "a missing type degrades to a generic result" do
      assert {"map-pin", "Result"} = PlaceIcons.for(nil)
      assert {"map-pin", "Result"} = PlaceIcons.for("")
    end
  end

  describe "the icon table" do
    test "every mapped icon exists in priv/icons" do
      # icon/2 renders "" for an unknown name rather than raising, so a typo
      # here would silently ship a blank square instead of failing a build.
      for {type, {name, _label}} <- PlaceIcons.table() do
        rendered = name |> AtlasWeb.IconHelpers.icon() |> Phoenix.HTML.safe_to_string()

        assert rendered =~ "<svg", "#{type} maps to missing icon #{name}"
      end
    end

    test "labels are human-facing, not raw OSM keys" do
      for {_type, {_name, label}} <- PlaceIcons.table() do
        assert label =~ ~r/^[A-Z]/, "#{label} should read as a label, not an OSM value"
      end
    end
  end
end
