defmodule Atlas.Maps.SearchTest do
  use ExUnit.Case, async: false
  alias Atlas.Maps.{Search, Result}

  setup do
    bypass = Bypass.open()
    photon_url = "http://localhost:#{bypass.port}"
    System.put_env("PHOTON_URL", photon_url)
    System.put_env("PHOTON_TIMEOUT", "1000")
    System.put_env("PLACEHOLDER_URL", photon_url)
    System.put_env("LIBPOSTAL_URL", photon_url)
    on_exit(fn -> System.delete_env("PHOTON_URL") end)
    {:ok, bypass: bypass}
  end

  test "autocomplete returns features + upstream_status=ok on Photon success", %{bypass: bypass} do
    Bypass.expect(bypass, fn conn ->
      case conn.request_path do
        "/parser" -> Plug.Conn.resp(conn, 200, ~s([{"label":"city","value":"berlin"}]))
        "/api" -> Plug.Conn.resp(conn, 200, ~s({"features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[13.4,52.5]},"properties":{"name":"Berlin","city":"Berlin","country":"Germany","osm_id":1,"osm_type":"R","osm_key":"place","osm_value":"city"}}]}))
        "/parser/search" -> Plug.Conn.resp(conn, 200, "[]")
      end
    end)

    {:ok, %Result{features: features, upstream_status: "ok"}} = Search.autocomplete(%{query: "berlin", limit: 5})
    assert [%{name: "Berlin", coords: %{lat: 52.5, lon: 13.4}}] = features
  end

  test "autocomplete returns {:error, %Unavailable{}} when Photon down", %{bypass: bypass} do
    Bypass.down(bypass)
    assert {:error, %Atlas.Maps.Upstream.Client.Unavailable{}} =
             Search.autocomplete(%{query: "berlin", limit: 5})
  end

  test "autocomplete normalizes Photon GeoJSON into Atlas feature shape", %{bypass: bypass} do
    Bypass.expect(bypass, fn conn ->
      case conn.request_path do
        "/parser" -> Plug.Conn.resp(conn, 200, ~s([{"label":"x","value":"berlin"}]))
        "/api" -> Plug.Conn.resp(conn, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"osm_id":1,"osm_type":"R","name":"Berlin","city":"Berlin","state":"Berlin","country":"Germany","postcode":"10115","osm_key":"place","osm_value":"city"}}]}))
        "/parser/search" -> Plug.Conn.resp(conn, 200, "[]")
      end
    end)

    {:ok, %Result{features: [feature]}} = Search.autocomplete(%{query: "berlin", limit: 5})
    assert feature.id == "R:1"
    assert feature.label == "Berlin, Berlin, Germany"
    assert feature.type == "city"
    assert feature.admin == %{country: "Germany", state: "Berlin", city: "Berlin", postcode: "10115"}
  end
end
