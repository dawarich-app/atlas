defmodule AtlasWeb.Api.V1.MapMatchControllerTest do
  use AtlasWeb.ConnCase, async: false

  alias Atlas.Maps.MapMatch

  # Decodes to [{52.5, 13.4}, {52.51, 13.41}] at precision 6.
  @leg_a "_ajccB_{zpX_pR_pR"

  @shape [
    %{lat: 52.5, lon: 13.4, time: 1_714_032_000, accuracy: 8},
    %{lat: 52.51, lon: 13.41, time: 1_714_032_030, accuracy: 6},
    %{lat: 52.52, lon: 13.42, time: 1_714_032_060}
  ]

  setup do
    bypass = Bypass.open()
    System.put_env("VALHALLA_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("VALHALLA_URL") end)
    {:ok, bypass: bypass}
  end

  defp submit(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/v1/map-match", Jason.encode!(body))
  end

  defp stub_trip(bypass, legs \\ ~s([{"shape":"#{@leg_a}"}])) do
    Bypass.expect_once(bypass, "POST", "/trace_route", fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"trip":{"summary":{"length":2.5},"legs":#{legs}}}))
    end)
  end

  describe "success" do
    test "returns the matched legs and echoes the request settings", %{
      conn: conn,
      bypass: bypass
    } do
      stub_trip(bypass)

      resp = conn |> submit(%{shape: @shape, mode: "auto"}) |> json_response(200)

      assert resp["data"]["summary"]["length"] == 2.5
      assert [%{"shape" => @leg_a}] = resp["data"]["legs"]
      assert resp["data"]["shape_format"] == "valhalla_encoded_polyline6"

      assert resp["meta"]["mode"] == "auto"
      assert resp["meta"]["shape_match"] == "map_snap"
      assert resp["meta"]["points"] == 3
      assert resp["meta"]["max_points"] == MapMatch.max_points()
    end

    test "format=geojson returns a decoded LineString", %{conn: conn, bypass: bypass} do
      stub_trip(bypass)

      resp =
        conn |> submit(%{shape: @shape, mode: "auto", format: "geojson"}) |> json_response(200)

      assert resp["data"]["shape_format"] == "geojson"

      assert resp["data"]["geometry"] == %{
               "type" => "LineString",
               "coordinates" => [[13.4, 52.5], [13.41, 52.51]]
             }
    end

    test "forwards per-point time and accuracy to Valhalla", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/trace_route", fn c ->
        {:ok, body, c} = Plug.Conn.read_body(c)
        [first, _, third] = Jason.decode!(body)["shape"]

        assert first["time"] == 1_714_032_000
        assert first["accuracy"] == 8
        refute Map.has_key?(third, "accuracy")

        Plug.Conn.resp(c, 200, ~s({"trip":{"legs":[]}}))
      end)

      assert conn |> submit(%{shape: @shape}) |> json_response(200)
    end

    test "forwards trace_options", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/trace_route", fn c ->
        {:ok, body, c} = Plug.Conn.read_body(c)

        assert Jason.decode!(body)["trace_options"] == %{
                 "search_radius" => 35,
                 "gps_accuracy" => 5,
                 "breakage_distance" => 2000
               }

        Plug.Conn.resp(c, 200, ~s({"trip":{"legs":[]}}))
      end)

      body = %{
        shape: @shape,
        search_radius: 35,
        gps_accuracy: 5,
        breakage_distance: 2000
      }

      assert conn |> submit(body) |> json_response(200)
    end

    test "defaults the mode to auto", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/trace_route", fn c ->
        {:ok, body, c} = Plug.Conn.read_body(c)
        assert Jason.decode!(body)["costing"] == "auto"
        Plug.Conn.resp(c, 200, ~s({"trip":{"legs":[]}}))
      end)

      assert conn |> submit(%{shape: @shape}) |> json_response(200)
    end
  end

  describe "request validation" do
    test "400 when shape is absent", %{conn: conn} do
      resp = conn |> submit(%{mode: "auto"}) |> json_response(400)

      assert resp["error"]["code"] == "MISSING_PARAM"
      assert resp["error"]["details"]["param"] == "shape"
    end

    test "400 when shape is not a list", %{conn: conn} do
      resp = conn |> submit(%{shape: "52.5,13.4"}) |> json_response(400)
      assert resp["error"]["code"] == "MISSING_PARAM"
    end

    test "422 when the trace has a single point", %{conn: conn} do
      resp = conn |> submit(%{shape: [%{lat: 52.5, lon: 13.4}]}) |> json_response(422)

      assert resp["error"]["code"] == "VALIDATION_ERROR"
      assert resp["error"]["message"] =~ "at least 2"
    end

    test "422 naming the offending index when a point is unparseable", %{conn: conn} do
      shape = [%{lat: 52.5, lon: 13.4}, %{lat: "nope", lon: 13.41}]

      resp = conn |> submit(%{shape: shape}) |> json_response(422)

      assert resp["error"]["code"] == "VALIDATION_ERROR"
      assert resp["error"]["details"]["index"] == 1
    end

    test "422 when a point is missing lon entirely", %{conn: conn} do
      resp =
        conn
        |> submit(%{shape: [%{lat: 52.5, lon: 13.4}, %{lat: 52.51}]})
        |> json_response(422)

      assert resp["error"]["details"]["index"] == 1
    end

    test "422 on an unsupported mode", %{conn: conn} do
      resp = conn |> submit(%{shape: @shape, mode: "rail"}) |> json_response(422)

      assert resp["error"]["code"] == "VALIDATION_ERROR"
      assert resp["error"]["message"] =~ "mode"
    end

    test "422 on an unsupported shape_match", %{conn: conn} do
      resp = conn |> submit(%{shape: @shape, shape_match: "vibes"}) |> json_response(422)

      assert resp["error"]["message"] =~ "shape_match"
    end

    test "422 on an unsupported format", %{conn: conn} do
      resp = conn |> submit(%{shape: @shape, format: "wkt"}) |> json_response(422)

      assert resp["error"]["message"] =~ "format"
    end

    test "422 when the trace exceeds the point cap", %{conn: conn} do
      System.put_env("MAP_MATCH_MAX_POINTS", "2")
      on_exit(fn -> System.delete_env("MAP_MATCH_MAX_POINTS") end)

      resp = conn |> submit(%{shape: @shape}) |> json_response(422)

      assert resp["error"]["code"] == "VALIDATION_ERROR"
      assert resp["error"]["details"]["max"] == 2
    end

    test "422 rather than 500 for a non-numeric JSON scalar", %{conn: conn} do
      # `true` and `%{}` are valid JSON but not coordinates. These reached
      # parse_float/1, which has clauses only for nil/binary/number, so the
      # request died with FunctionClauseError and the client saw a 500 — an
      # Atlas bug report for what is plainly bad input.
      for bad <- [true, false, %{"a" => 1}, [52.5]] do
        resp =
          conn
          |> submit(%{shape: [%{lat: 52.5, lon: 13.4}, %{lat: bad, lon: 13.41}]})
          |> json_response(422)

        assert resp["error"]["code"] == "VALIDATION_ERROR"
        assert resp["error"]["details"]["index"] == 1
      end
    end

    test "422 rather than silently truncating a comma decimal", %{conn: conn} do
      # Float.parse("52,5") returns {52.0, ",5"} — accepting it moved the point
      # half a degree (~55 km) with no error anywhere. A locale-confused client
      # must be told, not quietly relocated.
      resp =
        conn
        |> submit(%{shape: [%{lat: "52,5", lon: "13,4"}, %{lat: 52.51, lon: 13.41}]})
        |> json_response(422)

      assert resp["error"]["details"]["index"] == 0
    end

    test "still accepts numeric strings and integers", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/trace_route", fn c ->
        {:ok, body, c} = Plug.Conn.read_body(c)

        assert [%{"lat" => 52.5, "lon" => 13.4}, %{"lat" => 53.0, "lon" => 14.0}] =
                 Jason.decode!(body)["shape"]

        Plug.Conn.resp(c, 200, ~s({"trip":{"legs":[]}}))
      end)

      assert conn
             |> submit(%{shape: [%{lat: "52.5", lon: "13.4"}, %{lat: 53, lon: 14}]})
             |> json_response(200)
    end

    test "an unparseable point is rejected before Valhalla is called", %{
      conn: conn,
      bypass: bypass
    } do
      Bypass.stub(bypass, "POST", "/trace_route", fn c ->
        flunk("upstream must not be called for a malformed trace")
        Plug.Conn.resp(c, 200, "{}")
      end)

      conn
      |> submit(%{shape: [%{lat: 52.5, lon: 13.4}, %{lat: nil, lon: 13.41}]})
      |> response(422)
    end
  end

  describe "upstream failures" do
    test "422 rather than 502 when the trace cannot be snapped", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/trace_route", fn c ->
        Plug.Conn.resp(c, 400, ~s({"error_code":171,"error":"No suitable edges near location"}))
      end)

      resp = conn |> submit(%{shape: @shape}) |> json_response(422)

      assert resp["error"]["code"] == "VALIDATION_ERROR"
      assert resp["error"]["message"] =~ "No suitable edges near location"
      assert resp["error"]["details"]["upstream_error_code"] == 171
    end

    test "502 when Valhalla errors", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/trace_route", fn c ->
        Plug.Conn.resp(c, 500, "boom")
      end)

      resp = conn |> submit(%{shape: @shape}) |> json_response(502)
      assert resp["error"]["code"] == "UPSTREAM_ERROR"
    end

    test "503 when Valhalla is down", %{conn: conn, bypass: bypass} do
      Bypass.down(bypass)

      resp = conn |> submit(%{shape: @shape}) |> json_response(503)
      assert resp["error"]["code"] == "UPSTREAM_UNAVAILABLE"
    end
  end

  describe "openapi" do
    test "the endpoint is described in the published spec", %{conn: conn} do
      spec = conn |> get(~p"/api/v1/openapi.json") |> json_response(200)

      assert get_in(spec, ["paths", "/api/v1/map-match", "post", "summary"]) =~ "atch"
    end
  end
end
