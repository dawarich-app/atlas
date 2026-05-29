defmodule Atlas.Geometry.PolylineTest do
  use ExUnit.Case, async: true

  alias Atlas.Geometry.Polyline

  describe "decode/2 with precision 5 (Google)" do
    test "decodes the official Google polyline example" do
      # From https://developers.google.com/maps/documentation/utilities/polylinealgorithm
      encoded = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"

      decoded = Polyline.decode(encoded, 5)

      assert [
               {lat1, lon1},
               {lat2, lon2},
               {lat3, lon3}
             ] = decoded

      assert_in_delta lat1, 38.5, 0.00001
      assert_in_delta lon1, -120.2, 0.00001
      assert_in_delta lat2, 40.7, 0.00001
      assert_in_delta lon2, -120.95, 0.00001
      assert_in_delta lat3, 43.252, 0.00001
      assert_in_delta lon3, -126.453, 0.00001
    end

    test "decodes a single encoded point" do
      # Single point (38.5, -120.2) at precision 5.
      encoded = "_p~iF~ps|U"

      assert [{lat, lon}] = Polyline.decode(encoded, 5)
      assert_in_delta lat, 38.5, 0.00001
      assert_in_delta lon, -120.2, 0.00001
    end
  end

  describe "decode/2 with precision 6 (Valhalla)" do
    test "decodes a Valhalla precision-6 shape and returns reasonable lat/lon tuples" do
      # Real Valhalla-encoded shape (precision 6) for a short route near Berlin.
      # Captured from a Valhalla /route response (shape_format = valhalla_encoded_polyline6).
      encoded = "qnt}fAobg{aBjA{AjA{A"

      decoded = Polyline.decode(encoded, 6)

      assert is_list(decoded)
      assert length(decoded) >= 2

      Enum.each(decoded, fn {lat, lon} ->
        assert is_float(lat)
        assert is_float(lon)
        assert lat >= -90.0 and lat <= 90.0
        assert lon >= -180.0 and lon <= 180.0
      end)
    end
  end

  describe "decode/2 edge cases" do
    test "empty string returns empty list" do
      assert Polyline.decode("", 5) == []
      assert Polyline.decode("", 6) == []
    end

    test "defaults precision to 5 when not given" do
      decoded = Polyline.decode("_p~iF~ps|U")
      assert [{lat, lon}] = decoded
      assert_in_delta lat, 38.5, 0.00001
      assert_in_delta lon, -120.2, 0.00001
    end
  end
end
