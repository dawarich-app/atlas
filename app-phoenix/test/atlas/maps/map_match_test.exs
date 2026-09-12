defmodule Atlas.Maps.MapMatchTest do
  use ExUnit.Case, async: false

  alias Atlas.Geometry.Polyline
  alias Atlas.Maps.MapMatch
  alias Atlas.Maps.Upstream.Client

  @leg_a "_ajccB_{zpX_pR_pR"
  @shape [%{lat: 52.5, lon: 13.4}, %{lat: 52.51, lon: 13.41}, %{lat: 52.52, lon: 13.42}]

  setup do
    bypass = Bypass.open()
    System.put_env("VALHALLA_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("VALHALLA_URL") end)
    {:ok, bypass: bypass}
  end

  defp respond(bypass, status, body, path \\ "/trace_attributes") do
    Bypass.expect_once(bypass, "POST", path, fn conn -> Plug.Conn.resp(conn, status, body) end)
  end

  defp attributes(overrides \\ %{}) do
    Map.merge(
      %{
        "shape" => @leg_a,
        "edges" => [
          %{
            "length" => 1.25,
            "begin_shape_index" => 0,
            "end_shape_index" => 1,
            "end_node" => %{"elapsed_time" => 300.0}
          }
        ],
        "matched_points" => [
          %{
            "lat" => 52.5,
            "lon" => 13.4,
            "type" => "matched",
            "edge_index" => 0,
            "distance_along_edge" => 0.0,
            "distance_from_trace_point" => 3.0
          },
          %{
            "lat" => 52.51,
            "lon" => 13.41,
            "type" => "interpolated",
            "edge_index" => 0,
            "distance_along_edge" => 1.0,
            "distance_from_trace_point" => 9.0
          },
          %{"type" => "unmatched"}
        ],
        "confidence_score" => 0.91,
        "raw_score" => 12.5
      },
      overrides
    )
  end

  describe "match/1" do
    test "returns matched segments and per-point quality", %{bypass: bypass} do
      respond(bypass, 200, Jason.encode!(attributes()))

      assert {:ok, result} = MapMatch.match(shape: @shape, mode: "auto")

      assert result.features.summary == %{length: 1.25, time: 300.0}
      assert [%{shape: @leg_a, summary: %{length: 1.25}}] = result.features.legs
      assert result.features.shape_format == "valhalla_encoded_polyline6"
      assert Enum.map(result.features.matched_points, & &1.input_index) == [0, 1, 2]
      assert result.features.stats.matched == 1
      assert result.features.stats.interpolated == 1
      assert result.features.stats.unmatched == 1
      assert result.features.stats.segments == 1
      assert result.features.stats.mean_distance_from_trace_point == 6.0
      assert result.features.stats.p95_distance_from_trace_point == 9.0
      assert result.features.stats.confidence_score == 0.91
      assert result.upstream_status == "ok"
    end

    test "rejects a trace with fewer than two points" do
      assert {:error, :invalid, message, details} =
               MapMatch.match(shape: [%{lat: 52.5, lon: 13.4}], mode: "auto")

      assert message =~ "at least 2"
      assert details == %{param: "shape", min: 2}
    end

    test "rejects a trace over the point cap" do
      over = MapMatch.max_points() + 1
      shape = for _ <- 1..over, do: %{lat: 52.5, lon: 13.4}

      assert {:error, :too_many, max} = MapMatch.match(shape: shape, mode: "auto")
      assert max == MapMatch.max_points()
    end

    test "max_points/0 is overridable via MAP_MATCH_MAX_POINTS" do
      System.put_env("MAP_MATCH_MAX_POINTS", "7")
      on_exit(fn -> System.delete_env("MAP_MATCH_MAX_POINTS") end)
      assert MapMatch.max_points() == 7
    end
  end

  describe "geojson output" do
    test "returns a LineString for one matched segment", %{bypass: bypass} do
      respond(bypass, 200, Jason.encode!(attributes()))

      assert {:ok, result} = MapMatch.match(shape: @shape, mode: "auto", format: "geojson")
      assert result.features.shape_format == "geojson"

      assert result.features.geometry == %{
               type: "LineString",
               coordinates: [[13.4, 52.5], [13.41, 52.51]]
             }

      assert [%{geometry: %{type: "LineString"}}] = result.features.segments
      refute Map.has_key?(result.features, :legs)
    end

    test "preserves discontinuous paths as a MultiLineString", %{bypass: bypass} do
      points = Enum.map(@shape, &{&1.lat, &1.lon}) ++ [{52.6, 13.6}, {52.61, 13.61}]

      edges = [
        %{
          "length" => 1.0,
          "begin_shape_index" => 0,
          "end_shape_index" => 1,
          "end_node" => %{"elapsed_time" => 10.0}
        },
        %{
          "length" => 1.0,
          "begin_shape_index" => 1,
          "end_shape_index" => 2,
          "end_node" => %{"elapsed_time" => 20.0}
        },
        %{
          "length" => 2.0,
          "begin_shape_index" => 3,
          "end_shape_index" => 4,
          "end_node" => %{"elapsed_time" => 5.0}
        }
      ]

      body = attributes(%{"shape" => Polyline.encode(points, 6), "edges" => edges})
      respond(bypass, 200, Jason.encode!(body))

      assert {:ok, result} = MapMatch.match(shape: @shape, format: "geojson")
      assert result.features.summary == %{length: 4.0, time: 25.0}
      assert result.features.stats.segments == 2

      assert result.features.geometry == %{
               type: "MultiLineString",
               coordinates: [
                 [[13.4, 52.5], [13.41, 52.51], [13.42, 52.52]],
                 [[13.6, 52.6], [13.61, 52.61]]
               ]
             }
    end
  end

  describe "directions" do
    test "optionally preserves primary and alternate paths", %{bypass: bypass} do
      respond(bypass, 200, Jason.encode!(attributes()))

      respond(
        bypass,
        200,
        Jason.encode!(%{
          "trip" => %{"summary" => %{"length" => 1.0}, "legs" => [%{"shape" => "a"}]},
          "alternates" => [
            %{"summary" => %{"length" => 2.0}, "legs" => [%{"shape" => "b"}]}
          ]
        }),
        "/trace_route"
      )

      assert {:ok, result} =
               MapMatch.match(shape: @shape, include_directions: true, format: "geojson")

      assert [primary, alternate] = result.features.directions.paths
      assert primary["summary"]["length"] == 1.0
      assert alternate["summary"]["length"] == 2.0
    end
  end

  describe "upstream failures" do
    test "a 400 becomes a validation error", %{bypass: bypass} do
      respond(bypass, 400, ~s({"error_code":171,"error":"No suitable edges near location"}))

      assert {:error, :invalid, message, details} = MapMatch.match(shape: @shape, mode: "auto")
      assert message =~ "No suitable edges near location"
      assert details == %{param: "shape", upstream_error_code: 171}
    end

    test "a different rejection keeps its reason", %{bypass: bypass} do
      respond(
        bypass,
        400,
        ~s({"error_code":154,"error":"Path distance exceeds the max distance limit"})
      )

      assert {:error, :invalid, message, details} = MapMatch.match(shape: @shape, mode: "auto")
      assert message =~ "max distance limit"
      assert details.upstream_error_code == 154
    end

    test "an unreadable 400 uses the generic explanation", %{bypass: bypass} do
      respond(bypass, 400, "<html>gateway ate it</html>")

      assert {:error, :invalid, message, details} = MapMatch.match(shape: @shape, mode: "auto")
      assert message =~ "could not be matched"
      assert details == %{param: "shape"}
    end

    test "a 500 stays a BadResponse", %{bypass: bypass} do
      respond(bypass, 500, "boom")

      assert {:error, %Client.BadResponse{status: 500}} =
               MapMatch.match(shape: @shape, mode: "auto")
    end

    test "a dead upstream stays Unavailable", %{bypass: bypass} do
      Bypass.down(bypass)
      assert {:error, %Client.Unavailable{}} = MapMatch.match(shape: @shape, mode: "auto")
    end
  end
end
