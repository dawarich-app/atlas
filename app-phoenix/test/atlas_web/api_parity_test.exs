defmodule AtlasWeb.ApiParityTest do
  @moduledoc """
  Golden-file parity harness for `/api/v1/*`.

  Phased gate:

  * **M1** — structural parity only. When a captured Rails golden exists in
    `test/fixtures/goldens/<name>.json` we assert the top-level envelope
    keys (`data`, `meta`, ...) match. No goldens are captured at M1, so
    these assertions are inert — the harness wiring is what matters here.

  * **M5 Phase A** — upstream errors now map to 502/503 via
    `FallbackController`. Each test stubs Bypass so the endpoint returns
    200 with a valid envelope.

  * **M5 Phase E (this milestone)** — byte-diff parity gate is wired via
    `GoldenHelper.assert_byte_diff/2`. Until Rails goldens are captured
    manually (see `scripts/M5_GOLDENS_CAPTURE.md`), `assert_byte_diff/2`
    is a no-op against `nil`. Once `scripts/capture_rails_goldens.sh` has
    populated `test/fixtures/goldens/`, the harness asserts full JSON
    equality (modulo volatile `meta.timestamp` and `meta.request_id`).

  ## Manual capture procedure (run BEFORE the M4 §Task 9 destructive swap)

      cd ../app && bin/rails server -p 3000 &
      sleep 10
      cd ../app-phoenix
      bash scripts/capture_rails_goldens.sh http://localhost:3000
      mix test --only parity

  Full procedure: `scripts/M5_GOLDENS_CAPTURE.md`.
  """
  use AtlasWeb.ConnCase, async: false
  alias AtlasWeb.GoldenHelper

  @moduletag :parity

  setup do
    bypass = Bypass.open()
    url = "http://localhost:#{bypass.port}"

    Enum.each(
      ~w[PHOTON_URL PLACEHOLDER_URL LIBPOSTAL_URL OVERPASS_URL VALHALLA_URL OTP_URL],
      &System.put_env(&1, url)
    )

    Bypass.stub(bypass, "GET", "/api", fn c ->
      Plug.Conn.resp(c, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"Berlin"}}]}))
    end)

    Bypass.stub(bypass, "GET", "/reverse", fn c ->
      Plug.Conn.resp(c, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"Berlin"}}]}))
    end)

    Bypass.stub(bypass, "GET", "/parser", fn c -> Plug.Conn.resp(c, 200, "[]") end)
    Bypass.stub(bypass, "GET", "/parser/search", fn c -> Plug.Conn.resp(c, 200, "[]") end)
    Bypass.stub(bypass, "POST", "/route", fn c -> Plug.Conn.resp(c, 200, ~s({"trip":{"summary":{"length":1.0}}})) end)
    Bypass.stub(bypass, "GET", "/otp/routers/default/plan", fn c -> Plug.Conn.resp(c, 200, ~s({"plan":{"itineraries":[]}})) end)
    Bypass.stub(bypass, "POST", "/api/interpreter", fn c -> Plug.Conn.resp(c, 200, ~s({"elements":[]})) end)
    Bypass.stub(bypass, "GET", "/api/interpreter", fn c -> Plug.Conn.resp(c, 200, ~s({"elements":[]})) end)

    on_exit(fn ->
      Enum.each(
        ~w[PHOTON_URL PLACEHOLDER_URL LIBPOSTAL_URL OVERPASS_URL VALHALLA_URL OTP_URL],
        &System.delete_env/1
      )
    end)

    {:ok, bypass: bypass}
  end

  describe "GET /api/v1/search?q=berlin&limit=5" do
    test "matches golden envelope shape", %{conn: conn} do
      actual = conn |> get(~p"/api/v1/search?q=berlin&limit=5") |> json_response(200)
      expected = GoldenHelper.load("search-berlin")
      GoldenHelper.assert_envelope_shape(actual, expected)
      GoldenHelper.assert_byte_diff(actual, expected)
    end
  end

  describe "GET /api/v1/search?q=cafe&bbox=..." do
    test "matches golden envelope shape", %{conn: conn} do
      actual =
        conn
        |> get(~p"/api/v1/search?q=cafe&limit=10&bbox=13.0,52.0,14.0,53.0")
        |> json_response(200)

      expected = GoldenHelper.load("search-with-bbox")
      GoldenHelper.assert_envelope_shape(actual, expected)
      GoldenHelper.assert_byte_diff(actual, expected)
    end
  end

  describe "GET /api/v1/reverse?lat=...&lon=..." do
    test "matches golden envelope shape", %{conn: conn} do
      actual = conn |> get(~p"/api/v1/reverse?lat=52.5163&lon=13.3777") |> json_response(200)
      expected = GoldenHelper.load("reverse-brandenburg")
      GoldenHelper.assert_envelope_shape(actual, expected)
      GoldenHelper.assert_byte_diff(actual, expected)
    end
  end

  describe "POST /api/v1/reverse/batch" do
    test "matches golden envelope shape", %{conn: conn} do
      body = %{"coords" => [%{"lat" => 52.5, "lon" => 13.4}, %{"lat" => 48.1, "lon" => 11.5}]}

      actual =
        conn
        |> post(~p"/api/v1/reverse/batch", body)
        |> json_response(200)

      expected = GoldenHelper.load("reverse-batch-two")
      GoldenHelper.assert_envelope_shape(actual, expected)
      GoldenHelper.assert_byte_diff(actual, expected)
    end
  end

  describe "GET /api/v1/route" do
    test "matches golden envelope shape", %{conn: conn} do
      actual =
        conn
        |> get(~p"/api/v1/route?from=52.5,13.4&to=52.6,13.5&mode=auto")
        |> json_response(200)

      expected = GoldenHelper.load("route-auto")
      GoldenHelper.assert_envelope_shape(actual, expected)
      GoldenHelper.assert_byte_diff(actual, expected)
    end
  end

  describe "GET /api/v1/transit" do
    test "matches golden envelope shape", %{conn: conn} do
      actual =
        conn
        |> get(~p"/api/v1/transit?from=52.5,13.4&to=52.6,13.5")
        |> json_response(200)

      expected = GoldenHelper.load("transit-default")
      GoldenHelper.assert_envelope_shape(actual, expected)
      GoldenHelper.assert_byte_diff(actual, expected)
    end
  end

  describe "GET /api/v1/whats-here" do
    test "matches golden envelope shape", %{conn: conn} do
      actual = conn |> get(~p"/api/v1/whats-here?lat=52.5&lon=13.4") |> json_response(200)
      expected = GoldenHelper.load("whats-here-default")
      GoldenHelper.assert_envelope_shape(actual, expected)
      GoldenHelper.assert_byte_diff(actual, expected)
    end
  end

  describe "GET /api/v1/pois" do
    test "matches golden envelope shape", %{conn: conn} do
      actual =
        conn
        |> get(~p"/api/v1/pois?bbox=13.0,52.0,14.0,53.0&types=restaurant")
        |> json_response(200)

      expected = GoldenHelper.load("pois-food")
      GoldenHelper.assert_envelope_shape(actual, expected)
      GoldenHelper.assert_byte_diff(actual, expected)
    end
  end

  describe "GET /api/v1/pois/categories" do
    test "matches golden envelope shape", %{conn: conn} do
      actual = conn |> get(~p"/api/v1/pois/categories") |> json_response(200)
      expected = GoldenHelper.load("pois-categories")
      GoldenHelper.assert_envelope_shape(actual, expected)
      GoldenHelper.assert_byte_diff(actual, expected)
    end
  end

  describe "GET /api/v1/geocode" do
    test "matches golden envelope shape", %{conn: conn} do
      actual = conn |> get(~p"/api/v1/geocode?q=berlin") |> json_response(200)
      expected = GoldenHelper.load("geocode-berlin")
      GoldenHelper.assert_envelope_shape(actual, expected)
      GoldenHelper.assert_byte_diff(actual, expected)
    end
  end
end
