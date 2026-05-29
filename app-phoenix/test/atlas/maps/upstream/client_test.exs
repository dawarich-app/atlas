defmodule Atlas.Maps.Upstream.ClientTest do
  use ExUnit.Case, async: true
  alias Atlas.Maps.Upstream.Client
  alias Atlas.Maps.Upstream.Client.{Unavailable, BadResponse}

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, base_url: "http://localhost:#{bypass.port}"}
  end

  test "returns {:ok, body} on 200", %{bypass: bypass, base_url: base_url} do
    Bypass.expect_once(bypass, "GET", "/api", fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"hello":"world"}))
      |> Plug.Conn.put_resp_content_type("application/json")
    end)

    req = Client.build(base_url)
    assert {:ok, %{"hello" => "world"}} = Client.get(req, "/api")
  end

  test "returns {:error, BadResponse} on 500", %{bypass: bypass, base_url: base_url} do
    Bypass.expect_once(bypass, "GET", "/api", fn conn -> Plug.Conn.resp(conn, 500, "boom") end)
    req = Client.build(base_url)
    assert {:error, %BadResponse{status: 500}} = Client.get(req, "/api")
  end

  test "returns {:error, Unavailable} when port is closed", %{bypass: bypass, base_url: base_url} do
    Bypass.down(bypass)
    req = Client.build(base_url, open_timeout: 100, timeout: 100)
    assert {:error, %Unavailable{}} = Client.get(req, "/api")
  end

  test "encodes repeated query keys", %{bypass: bypass, base_url: base_url} do
    Bypass.expect_once(bypass, "GET", "/api", fn conn ->
      assert conn.query_string == "osm_tag=amenity%3Acafe&osm_tag=tourism%3Ahotel"
      Plug.Conn.resp(conn, 200, "{}")
    end)

    req = Client.build(base_url)
    Client.get(req, "/api", [{"osm_tag", "amenity:cafe"}, {"osm_tag", "tourism:hotel"}])
  end
end
