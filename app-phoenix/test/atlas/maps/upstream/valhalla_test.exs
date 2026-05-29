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
      assert [%{"lat" => 52.5, "lon" => 13.4}, %{"lat" => 52.6, "lon" => 13.5}] = json["locations"]
      assert get_in(json, ["directions_options", "units"]) == "kilometers"
      Plug.Conn.resp(conn, 200, ~s({"trip":{"summary":{"length":12.3}}}))
    end)

    assert {:ok, %{"trip" => _}} = Valhalla.route(req, from: %{lat: 52.5, lon: 13.4}, to: %{lat: 52.6, lon: 13.5}, mode: "auto")
  end

  test "route/2 includes costing_options for auto with avoid flags", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, "POST", "/route", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      json = Jason.decode!(body)
      assert json["costing_options"]["auto"]["use_tolls"] == 0.0
      assert json["costing_options"]["auto"]["use_highways"] == 0.0
      Plug.Conn.resp(conn, 200, "{}")
    end)

    Valhalla.route(req, from: %{lat: 52.5, lon: 13.4}, to: %{lat: 52.6, lon: 13.5}, mode: "auto", options: %{avoid_tolls: true, avoid_highways: true})
  end

  test "route/2 raises on invalid mode", %{req: req} do
    assert_raise ArgumentError, ~r/invalid mode/, fn ->
      Valhalla.route(req, from: %{lat: 0, lon: 0}, to: %{lat: 1, lon: 1}, mode: "submarine")
    end
  end
end
