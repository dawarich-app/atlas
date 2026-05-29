defmodule Atlas.Maps.RouteTest do
  use ExUnit.Case, async: false
  alias Atlas.Maps.{Route, Result}

  setup do
    bypass = Bypass.open()
    System.put_env("VALHALLA_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("VALHALLA_URL") end)
    {:ok, bypass: bypass}
  end

  test "plan flattens result to summary + legs + shape_format", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/route", fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"trip":{"summary":{"length":1.2},"legs":[{"shape":"abc","maneuvers":[]}]}}))
    end)

    assert {:ok, %Result{features: features, upstream_status: "ok"}} =
             Route.plan(from: %{lat: 52.5, lon: 13.4}, to: %{lat: 52.6, lon: 13.5}, mode: "auto")

    assert features.summary == %{"length" => 1.2}
    assert [%{"shape" => "abc"}] = features.legs
    assert features.shape_format == "valhalla_encoded_polyline6"
  end

  test "plan returns {:error, %Unavailable{}} when Valhalla down", %{bypass: bypass} do
    Bypass.down(bypass)

    assert {:error, %Atlas.Maps.Upstream.Client.Unavailable{}} =
             Route.plan(from: %{lat: 0, lon: 0}, to: %{lat: 1, lon: 1}, mode: "auto")
  end
end
