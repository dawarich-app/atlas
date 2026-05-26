defmodule AtlasWeb.ApiParityTest do
  @moduledoc """
  Golden-file parity harness for `/api/v1/*`.

  Phased gate:

  * **M1 (this milestone)** — structural parity only. When a captured Rails
    golden exists in `test/fixtures/goldens/<name>.json` we assert the
    top-level envelope keys (`data`, `meta`, ...) match. No goldens are
    captured at M1, so these assertions are inert — the harness wiring is
    what matters here. Sidecars are not stubbed; endpoints respond with
    `upstream=unavailable` or `400` depending on missing-param handling.

  * **M4 (cutover)** — byte-diff parity. Capture Rails traffic with
    `vcr`-style recording, stub the upstream HTTP responses identically
    against Phoenix, then enable `GoldenHelper.diff/2` to require full
    JSON equality (modulo volatile `meta` fields).
  """
  use AtlasWeb.ConnCase, async: false
  alias AtlasWeb.GoldenHelper

  @moduletag :parity

  describe "GET /api/v1/search?q=berlin&limit=5" do
    test "matches golden envelope shape", %{conn: conn} do
      stub_sidecars_for_golden("search-berlin")
      actual = conn |> get(~p"/api/v1/search?q=berlin&limit=5") |> json_response(200)
      expected = GoldenHelper.load("search-berlin")
      GoldenHelper.assert_envelope_shape(actual, expected)
    end
  end

  describe "GET /api/v1/search?q=cafe&bbox=..." do
    test "matches golden envelope shape", %{conn: conn} do
      stub_sidecars_for_golden("search-with-bbox")

      actual =
        conn
        |> get(~p"/api/v1/search?q=cafe&limit=10&bbox=13.0,52.0,14.0,53.0")
        |> json_response(200)

      expected = GoldenHelper.load("search-with-bbox")
      GoldenHelper.assert_envelope_shape(actual, expected)
    end
  end

  describe "GET /api/v1/reverse?lat=...&lon=..." do
    test "matches golden envelope shape", %{conn: conn} do
      stub_sidecars_for_golden("reverse-brandenburg")
      actual = conn |> get(~p"/api/v1/reverse?lat=52.5163&lon=13.3777") |> json_response(200)
      expected = GoldenHelper.load("reverse-brandenburg")
      GoldenHelper.assert_envelope_shape(actual, expected)
    end
  end

  describe "POST /api/v1/reverse/batch" do
    test "matches golden envelope shape", %{conn: conn} do
      stub_sidecars_for_golden("reverse-batch-two")

      body = %{"coords" => [%{"lat" => 52.5, "lon" => 13.4}, %{"lat" => 48.1, "lon" => 11.5}]}

      actual =
        conn
        |> post(~p"/api/v1/reverse/batch", body)
        |> json_response(200)

      expected = GoldenHelper.load("reverse-batch-two")
      GoldenHelper.assert_envelope_shape(actual, expected)
    end
  end

  describe "GET /api/v1/route" do
    test "matches golden envelope shape", %{conn: conn} do
      stub_sidecars_for_golden("route-auto")

      actual =
        conn
        |> get(~p"/api/v1/route?from=52.5,13.4&to=52.6,13.5&mode=auto")
        |> json_response(200)

      expected = GoldenHelper.load("route-auto")
      GoldenHelper.assert_envelope_shape(actual, expected)
    end
  end

  describe "GET /api/v1/transit" do
    test "matches golden envelope shape", %{conn: conn} do
      stub_sidecars_for_golden("transit-default")

      actual =
        conn
        |> get(~p"/api/v1/transit?from=52.5,13.4&to=52.6,13.5")
        |> json_response(200)

      expected = GoldenHelper.load("transit-default")
      GoldenHelper.assert_envelope_shape(actual, expected)
    end
  end

  describe "GET /api/v1/whats-here" do
    test "matches golden envelope shape", %{conn: conn} do
      stub_sidecars_for_golden("whats-here-default")
      actual = conn |> get(~p"/api/v1/whats-here?lat=52.5&lon=13.4") |> json_response(200)
      expected = GoldenHelper.load("whats-here-default")
      GoldenHelper.assert_envelope_shape(actual, expected)
    end
  end

  describe "GET /api/v1/pois" do
    # Note: M1 Phoenix POIs uses `bbox=w,s,e,n` (per spec §5); the Rails golden
    # used `lat/lon/radius/category`. The M4 byte-diff phase will reconcile
    # — for M1 we exercise the Phoenix-native shape.
    test "matches golden envelope shape", %{conn: conn} do
      stub_sidecars_for_golden("pois-food")

      actual =
        conn
        |> get(~p"/api/v1/pois?bbox=13.0,52.0,14.0,53.0&types=food")
        |> json_response(200)

      expected = GoldenHelper.load("pois-food")
      GoldenHelper.assert_envelope_shape(actual, expected)
    end
  end

  describe "GET /api/v1/pois/categories" do
    test "matches golden envelope shape", %{conn: conn} do
      stub_sidecars_for_golden("pois-categories")
      actual = conn |> get(~p"/api/v1/pois/categories") |> json_response(200)
      expected = GoldenHelper.load("pois-categories")
      GoldenHelper.assert_envelope_shape(actual, expected)
    end
  end

  describe "GET /api/v1/geocode" do
    test "matches golden envelope shape", %{conn: conn} do
      stub_sidecars_for_golden("geocode-berlin")
      actual = conn |> get(~p"/api/v1/geocode?q=berlin") |> json_response(200)
      expected = GoldenHelper.load("geocode-berlin")
      GoldenHelper.assert_envelope_shape(actual, expected)
    end
  end

  # Sidecar stubbing for byte-diff parity arrives in M4 (see moduledoc).
  defp stub_sidecars_for_golden(_name), do: :ok
end
