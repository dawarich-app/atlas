defmodule Atlas.Maps.Upstream.ValhallaTest do
  use ExUnit.Case, async: true
  alias Atlas.Maps.Upstream.{Client, Valhalla}

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, req: Client.build("http://localhost:#{bypass.port}")}
  end

  test "route/2 POSTs JSON body with locations + costing", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, "POST", "/route", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      json = Jason.decode!(body)
      assert json["costing"] == "auto"

      assert [%{"lat" => 52.5, "lon" => 13.4}, %{"lat" => 52.6, "lon" => 13.5}] =
               json["locations"]

      assert get_in(json, ["directions_options", "units"]) == "kilometers"
      Plug.Conn.resp(conn, 200, ~s({"trip":{"summary":{"length":12.3}}}))
    end)

    assert {:ok, %{"trip" => _}} =
             Valhalla.route(req,
               from: %{lat: 52.5, lon: 13.4},
               to: %{lat: 52.6, lon: 13.5},
               mode: "auto"
             )
  end

  test "route/2 includes costing_options for auto with avoid flags", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, "POST", "/route", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      json = Jason.decode!(body)
      assert json["costing_options"]["auto"]["use_tolls"] == 0.0
      assert json["costing_options"]["auto"]["use_highways"] == 0.0
      Plug.Conn.resp(conn, 200, "{}")
    end)

    Valhalla.route(req,
      from: %{lat: 52.5, lon: 13.4},
      to: %{lat: 52.6, lon: 13.5},
      mode: "auto",
      options: %{avoid_tolls: true, avoid_highways: true}
    )
  end

  test "route/2 raises on invalid mode", %{req: req} do
    assert_raise ArgumentError, ~r/invalid mode/, fn ->
      Valhalla.route(req, from: %{lat: 0, lon: 0}, to: %{lat: 1, lon: 1}, mode: "submarine")
    end
  end

  describe "trace_route/2" do
    test "POSTs the shape, costing and shape_match to /trace_route", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "POST", "/trace_route", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        json = Jason.decode!(body)

        assert json["costing"] == "auto"
        assert json["shape_match"] == "map_snap"
        assert [%{"lat" => 52.5, "lon" => 13.4}, %{"lat" => 52.6, "lon" => 13.5}] = json["shape"]
        assert get_in(json, ["directions_options", "units"]) == "kilometers"

        Plug.Conn.resp(conn, 200, ~s({"trip":{"summary":{"length":1.0}}}))
      end)

      assert {:ok, %{"trip" => _}} =
               Valhalla.trace_route(req,
                 shape: [%{lat: 52.5, lon: 13.4}, %{lat: 52.6, lon: 13.5}],
                 mode: "auto"
               )
    end

    test "carries per-point time and accuracy when present", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "POST", "/trace_route", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        json = Jason.decode!(body)

        assert [first, second] = json["shape"]
        assert first["time"] == 1_714_032_000
        assert first["accuracy"] == 8.0
        # Points without the optional keys must not carry nulls: Valhalla
        # rejects a null `time` on an otherwise valid trace.
        refute Map.has_key?(second, "time")
        refute Map.has_key?(second, "accuracy")

        Plug.Conn.resp(conn, 200, "{}")
      end)

      Valhalla.trace_route(req,
        shape: [
          %{lat: 52.5, lon: 13.4, time: 1_714_032_000, accuracy: 8.0},
          # Explicit nils, because that is what the controller emits for a
          # point that carried neither field. An omitted key would be dropped
          # by Map.take/2 anyway and would not exercise the rejection at all.
          %{lat: 52.6, lon: 13.5, time: nil, accuracy: nil}
        ],
        mode: "auto"
      )
    end

    test "sends only the trace_options that were supplied", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "POST", "/trace_route", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        json = Jason.decode!(body)

        assert json["trace_options"] == %{"search_radius" => 35, "gps_accuracy" => 5}

        Plug.Conn.resp(conn, 200, "{}")
      end)

      Valhalla.trace_route(req,
        shape: [%{lat: 52.5, lon: 13.4}, %{lat: 52.6, lon: 13.5}],
        mode: "auto",
        trace_options: %{search_radius: 35, gps_accuracy: 5}
      )
    end

    test "omits trace_options entirely when none were supplied", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "POST", "/trace_route", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        refute Map.has_key?(Jason.decode!(body), "trace_options")
        Plug.Conn.resp(conn, 200, "{}")
      end)

      Valhalla.trace_route(req,
        shape: [%{lat: 52.5, lon: 13.4}, %{lat: 52.6, lon: 13.5}],
        mode: "auto"
      )
    end

    test "honours an explicit shape_match", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "POST", "/trace_route", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["shape_match"] == "edge_walk"
        Plug.Conn.resp(conn, 200, "{}")
      end)

      Valhalla.trace_route(req,
        shape: [%{lat: 52.5, lon: 13.4}, %{lat: 52.6, lon: 13.5}],
        mode: "auto",
        shape_match: "edge_walk"
      )
    end

    test "raises on invalid mode", %{req: req} do
      assert_raise ArgumentError, ~r/invalid mode/, fn ->
        Valhalla.trace_route(req, shape: [%{lat: 0, lon: 0}], mode: "submarine")
      end
    end

    test "raises on invalid shape_match", %{req: req} do
      assert_raise ArgumentError, ~r/invalid shape_match/, fn ->
        Valhalla.trace_route(req, shape: [%{lat: 0, lon: 0}], mode: "auto", shape_match: "vibes")
      end
    end
  end

  describe "trace_attributes/2" do
    test "POSTs the trace to /trace_attributes", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "POST", "/trace_attributes", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        json = Jason.decode!(body)

        assert json["costing"] == "bicycle"
        assert json["shape_match"] == "map_snap"

        assert [
                 %{"lat" => 52.5, "lon" => 13.4, "time" => 100, "accuracy" => 7},
                 %{"lat" => 52.6, "lon" => 13.5}
               ] = json["shape"]

        assert json["trace_options"] == %{"search_radius" => 35}
        refute Map.has_key?(json, "directions_options")

        Plug.Conn.resp(conn, 200, ~s({"shape":"abc","matched_points":[]}))
      end)

      assert {:ok, %{"shape" => "abc"}} =
               Valhalla.trace_attributes(req,
                 shape: [
                   %{lat: 52.5, lon: 13.4, time: 100, accuracy: 7},
                   %{lat: 52.6, lon: 13.5}
                 ],
                 mode: "bicycle",
                 trace_options: %{search_radius: 35}
               )
    end

    test "validates shape_match", %{req: req} do
      assert_raise ArgumentError, ~r/invalid shape_match/, fn ->
        Valhalla.trace_attributes(req,
          shape: [%{lat: 52.5, lon: 13.4}, %{lat: 52.6, lon: 13.5}],
          shape_match: "vibes"
        )
      end
    end
  end

  describe "match_default/0" do
    test "allows a longer receive timeout than point-to-point routing" do
      # A 5000-point trace takes far longer to match than an A-to-B route, so
      # the 15s route ceiling would abort perfectly healthy matches.
      assert Valhalla.match_default().options[:receive_timeout] >
               Valhalla.default().options[:receive_timeout]
    end

    test "reads VALHALLA_MATCH_TIMEOUT" do
      System.put_env("VALHALLA_MATCH_TIMEOUT", "90000")
      on_exit(fn -> System.delete_env("VALHALLA_MATCH_TIMEOUT") end)

      assert Valhalla.match_default().options[:receive_timeout] == 90_000
    end
  end
end
