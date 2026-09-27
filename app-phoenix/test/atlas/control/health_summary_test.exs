defmodule Atlas.Control.HealthSummaryTest do
  use Atlas.DataCase, async: true

  alias Atlas.Control.{Health, Service}
  alias Atlas.Repo

  test "live Photon status overrides a stale stopped container state" do
    Repo.insert!(%Service{name: "photon", profile: "geocoding", status: :stopped})
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "GET", "/status", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"status":"Ok"}))
    end)

    health = Health.summary(photon_url: "http://localhost:#{bypass.port}")

    assert health.capabilities["geocoding"] == "up"
  end

  test "a failing Photon status overrides a stale ready container state" do
    Repo.insert!(%Service{name: "photon", profile: "geocoding", status: :ready})
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "GET", "/status", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"status":"Importing"}))
    end)

    health = Health.summary(photon_url: "http://localhost:#{bypass.port}")

    assert health.capabilities["geocoding"] == "down"
  end

  test "a non-200 Photon response is down even if the container is ready" do
    Repo.insert!(%Service{name: "photon", profile: "geocoding", status: :ready})
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "GET", "/status", fn conn ->
      Plug.Conn.resp(conn, 503, "unavailable")
    end)

    assert Health.summary(photon_url: "http://localhost:#{bypass.port}").capabilities[
             "geocoding"
           ] == "down"
  end

  test "without a configured Photon URL the container state remains authoritative" do
    Repo.insert!(%Service{name: "photon", profile: "geocoding", status: :ready})

    assert Health.summary(photon_url: nil).capabilities["geocoding"] == "up"
  end
end
