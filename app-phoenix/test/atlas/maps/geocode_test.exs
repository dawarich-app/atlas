defmodule Atlas.Maps.GeocodeTest do
  use ExUnit.Case, async: false
  alias Atlas.Maps.{Geocode, Result}

  setup do
    bypass = Bypass.open()
    System.put_env("PHOTON_URL", "http://localhost:#{bypass.port}")
    System.put_env("PLACEHOLDER_URL", "http://localhost:#{bypass.port}")
    System.put_env("LIBPOSTAL_URL", "http://localhost:#{bypass.port}")
    on_exit(fn ->
      System.delete_env("PHOTON_URL")
      System.delete_env("PLACEHOLDER_URL")
      System.delete_env("LIBPOSTAL_URL")
    end)
    {:ok, bypass: bypass}
  end

  test "lookup with query returns {:ok, :forward, Result} on Photon success", %{bypass: bypass} do
    Bypass.expect(bypass, fn conn ->
      case conn.request_path do
        "/parser" -> Plug.Conn.resp(conn, 200, ~s([{"label":"x","value":"X"}]))
        "/api" -> Plug.Conn.resp(conn, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"X"}}]}))
        "/parser/search" -> Plug.Conn.resp(conn, 200, "[]")
      end
    end)

    assert {:ok, :forward, %Result{features: features, upstream_status: "ok"}} = Geocode.lookup(query: "X")
    assert [%{name: "X"}] = features
  end

  test "lookup with lat+lon returns {:ok, :reverse, Result} on Photon reverse success", %{bypass: bypass} do
    Bypass.expect(bypass, fn conn ->
      case conn.request_path do
        "/reverse" -> Plug.Conn.resp(conn, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"BG"}}]}))
        "/parser/search" -> Plug.Conn.resp(conn, 200, "[]")
      end
    end)

    assert {:ok, :reverse, %Result{features: %{here: here}, upstream_status: "ok"}} =
             Geocode.lookup(lat: 52.5, lon: 13.4)

    assert here.name == "BG"
  end

  test "lookup with neither q nor lat+lon returns {:error, :missing, _}" do
    assert {:error, :missing, "q or lat+lon"} = Geocode.lookup([])
  end

  test "lookup with query returns {:error, %Unavailable{}} when down", %{bypass: bypass} do
    Bypass.down(bypass)
    assert {:error, %Atlas.Maps.Upstream.Client.Unavailable{}} = Geocode.lookup(query: "X")
  end
end
