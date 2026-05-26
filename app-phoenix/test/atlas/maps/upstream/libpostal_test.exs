defmodule Atlas.Maps.Upstream.LibpostalTest do
  use ExUnit.Case, async: true
  alias Atlas.Maps.Upstream.{Client, Libpostal}

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, req: Client.build("http://localhost:#{bypass.port}")}
  end

  test "normalize/2 returns parsed components", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, "GET", "/parser", fn conn ->
      assert conn.query_string =~ "address=" <> URI.encode_www_form("Berlin Hbf")
      Plug.Conn.resp(conn, 200, ~s([{"label":"city","value":"berlin hauptbahnhof"}]))
    end)

    assert %{query: "berlin hauptbahnhof", components: [%{"label" => "city", "value" => _}]} = Libpostal.normalize(req, "Berlin Hbf")
  end

  test "normalize/2 falls back to original query on upstream failure", %{bypass: bypass, req: req} do
    Bypass.down(bypass)
    assert %{query: "Berlin Hbf", components: []} = Libpostal.normalize(req, "Berlin Hbf")
  end

  test "normalize/2 falls back when response is non-list", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, "GET", "/parser", fn conn -> Plug.Conn.resp(conn, 200, ~s({"error":"oops"})) end)
    assert %{query: "Berlin Hbf", components: []} = Libpostal.normalize(req, "Berlin Hbf")
  end
end
