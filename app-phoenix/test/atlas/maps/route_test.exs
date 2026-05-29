defmodule Atlas.Maps.RouteTest do
  use ExUnit.Case, async: false
  alias Atlas.Maps.{Route, Result}

  setup do
    bypass = Bypass.open()
    System.put_env("VALHALLA_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("VALHALLA_URL") end)
    {:ok, bypass: bypass}
  end

  test "plan returns trip + ok status", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/route", fn conn -> Plug.Conn.resp(conn, 200, ~s({"trip":{"summary":{"length":1.2}}})) end)
    assert {:ok, %Result{features: %{trip: %{"summary" => _}}, upstream_status: "ok"}} =
             Route.plan(from: %{lat: 52.5, lon: 13.4}, to: %{lat: 52.6, lon: 13.5}, mode: "auto")
  end

  test "plan returns {:error, %Unavailable{}} when Valhalla down", %{bypass: bypass} do
    Bypass.down(bypass)

    assert {:error, %Atlas.Maps.Upstream.Client.Unavailable{}} =
             Route.plan(from: %{lat: 0, lon: 0}, to: %{lat: 1, lon: 1}, mode: "auto")
  end
end
