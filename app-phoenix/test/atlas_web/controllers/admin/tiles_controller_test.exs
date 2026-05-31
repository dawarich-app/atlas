defmodule AtlasWeb.Admin.TilesControllerTest do
  use AtlasWeb.ConnCase, async: false

  alias Atlas.Settings

  setup do
    System.put_env("ADMIN_USERNAME", "admin")
    System.put_env("ADMIN_PASSWORD", "s3cret")

    on_exit(fn ->
      Enum.each(~w[ADMIN_USERNAME ADMIN_PASSWORD], &System.delete_env/1)
    end)

    conn =
      build_conn()
      |> put_req_header("authorization", "Basic " <> Base.encode64("admin:s3cret"))

    {:ok, conn: conn}
  end

  test "GET /admin/tiles.json returns current state envelope", %{conn: conn} do
    Settings.set("tiles_url", "https://tiles.example/style.json")
    Settings.set("tiles_theme", "atlas-dark")

    resp = conn |> get(~p"/admin/tiles.json") |> json_response(200)

    assert resp["data"]["tiles_url"] == "https://tiles.example/style.json"
    assert resp["data"]["theme"] == "atlas-dark"
    assert resp["data"]["source"] == "external"
  end

  test "POST /admin/tiles.json persists tiles_url and theme", %{conn: conn} do
    body = %{"tiles_url" => "https://new.example/region.pmtiles", "theme" => "atlas-light"}

    resp =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/admin/tiles.json", Jason.encode!(body))
      |> json_response(200)

    assert resp["data"]["tiles_url"] == "https://new.example/region.pmtiles"
    assert resp["data"]["theme"] == "atlas-light"
    assert Settings.get("tiles_url") == "https://new.example/region.pmtiles"
  end

  test "POST /admin/tiles.json with sidecar URL returns source=sidecar", %{conn: conn} do
    body = %{"tiles_url" => "http://atlas-control:5000/tiles.pmtiles"}

    resp =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/admin/tiles.json", Jason.encode!(body))
      |> json_response(200)

    assert resp["data"]["source"] == "sidecar"
  end

  test "POST /admin/tiles.json with bad theme returns 422", %{conn: conn} do
    body = %{"theme" => "neon"}

    resp =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/admin/tiles.json", Jason.encode!(body))
      |> json_response(422)

    assert resp["error"]["code"] == "BAD_REQUEST"
  end
end
