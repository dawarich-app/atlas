defmodule Atlas.Maps.ReverseBatchTest do
  use ExUnit.Case, async: false
  alias Atlas.Maps.Reverse

  setup do
    Cachex.clear(:reverse_cache)
    bypass = Bypass.open()
    System.put_env("PHOTON_URL", "http://localhost:#{bypass.port}")
    System.put_env("PLACEHOLDER_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("PHOTON_URL"); System.delete_env("PLACEHOLDER_URL") end)
    {:ok, bypass: bypass}
  end

  test "batch returns one result per input coord with cache hits=0 misses=N on first run", %{bypass: bypass} do
    Bypass.expect(bypass, fn conn ->
      case conn.request_path do
        "/reverse" -> Plug.Conn.resp(conn, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"X","city":"Y","country":"Z"}}]}))
        "/parser/search" -> Plug.Conn.resp(conn, 200, "[]")
      end
    end)

    coords = [%{lat: 52.5, lon: 13.4}, %{lat: 48.1, lon: 11.5}]
    result = Reverse.batch(%{coords: coords})

    assert length(result.results) == 2
    assert result.cache_hits == 0
    assert result.cache_misses == 2
  end

  test "batch dedupes coords within grid precision (6 decimals)", %{bypass: bypass} do
    Bypass.expect(bypass, fn conn ->
      case conn.request_path do
        "/reverse" -> Plug.Conn.resp(conn, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"X","city":"Y","country":"Z"}}]}))
        "/parser/search" -> Plug.Conn.resp(conn, 200, "[]")
      end
    end)

    coords = [%{lat: 52.5000001, lon: 13.4000001}, %{lat: 52.5000002, lon: 13.4000002}]
    result = Reverse.batch(%{coords: coords})
    assert length(result.results) == 2
  end

  test "batch caps at MAX_COORDS", %{bypass: bypass} do
    Bypass.stub(bypass, "GET", "/reverse", fn conn -> Plug.Conn.resp(conn, 200, ~s({"features":[]})) end)
    Bypass.stub(bypass, "GET", "/parser/search", fn conn -> Plug.Conn.resp(conn, 200, "[]") end)

    coords = for n <- 1..1500, do: %{lat: 52.0 + n / 10000, lon: 13.0 + n / 10000}
    result = Reverse.batch(%{coords: coords})
    assert length(result.results) <= 1000
  end
end
