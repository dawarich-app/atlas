defmodule Atlas.Maps.TransitTest do
  use ExUnit.Case, async: false
  alias Atlas.Maps.{Transit, Result}

  setup do
    bypass = Bypass.open()
    System.put_env("OTP_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("OTP_URL") end)
    {:ok, bypass: bypass}
  end

  test "plan returns itineraries + ok status", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/otp/routers/default/plan", fn conn -> Plug.Conn.resp(conn, 200, ~s({"plan":{"itineraries":[{"duration":600}]}})) end)
    assert {:ok, %Result{features: %{plan: %{"itineraries" => [_]}}, upstream_status: "ok"}} =
             Transit.plan(from: %{lat: 52.5, lon: 13.4}, to: %{lat: 52.6, lon: 13.5})
  end

  test "plan returns {:error, %Unavailable{}} when OTP down", %{bypass: bypass} do
    Bypass.down(bypass)

    assert {:error, %Atlas.Maps.Upstream.Client.Unavailable{}} =
             Transit.plan(from: %{lat: 0, lon: 0}, to: %{lat: 1, lon: 1})
  end
end
