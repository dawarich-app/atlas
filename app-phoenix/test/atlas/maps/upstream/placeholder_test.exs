defmodule Atlas.Maps.Upstream.PlaceholderTest do
  use ExUnit.Case, async: true
  alias Atlas.Maps.Upstream.{Client, Placeholder}

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, req: Client.build("http://localhost:#{bypass.port}")}
  end

  test "admin_for/2 returns admin map from /parser/search response", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, "GET", "/parser/search", fn conn ->
      assert conn.query_string =~ "text=Berlin"
      Plug.Conn.resp(conn, 200, ~s([{"name":"Berlin","placetype":"locality","lineage":[{"country":{"name":"Germany"},"region":{"name":"Berlin"},"locality":{"name":"Berlin"}}]}]))
    end)

    assert %{country: "Germany", state: "Berlin", city: "Berlin"} = Placeholder.admin_for(req, text: "Berlin")
  end

  test "admin_for/2 returns nil on empty response", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, "GET", "/parser/search", fn conn -> Plug.Conn.resp(conn, 200, "[]") end)
    assert nil == Placeholder.admin_for(req, text: "nowhere")
  end

  test "admin_for/2 returns nil when service unavailable", %{bypass: bypass, req: req} do
    Bypass.down(bypass)
    assert nil == Placeholder.admin_for(req, text: "Berlin")
  end
end
