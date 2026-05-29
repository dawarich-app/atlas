defmodule Atlas.Maps.Upstream.OtpTest do
  use ExUnit.Case, async: true
  alias Atlas.Maps.Upstream.{Client, Otp}

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, req: Client.build("http://localhost:#{bypass.port}")}
  end

  test "plan/2 hits /otp/routers/default/plan with required params", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, "GET", "/otp/routers/default/plan", fn conn ->
      assert conn.query_string =~ "fromPlace=52.5%2C13.4"
      assert conn.query_string =~ "toPlace=52.6%2C13.5"
      assert conn.query_string =~ "mode=TRANSIT%2CWALK"
      Plug.Conn.resp(conn, 200, ~s({"plan":{"itineraries":[]}}))
    end)

    assert {:ok, %{"plan" => _}} = Otp.plan(req, from: %{lat: 52.5, lon: 13.4}, to: %{lat: 52.6, lon: 13.5})
  end
end
