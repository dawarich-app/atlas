defmodule AtlasWeb.Admin.RegionsControllerTest do
  use AtlasWeb.ConnCase, async: false

  alias Atlas.Control.RegionSelection
  alias Atlas.Repo

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

  test "POST /admin/regions.json persists the new selection", %{conn: conn} do
    body = %{"selected" => ["berlin", "germany"]}

    resp =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/admin/regions.json", Jason.encode!(body))
      |> json_response(200)

    assert resp["data"]["selected"] == ["berlin", "germany"]
    assert is_list(resp["data"]["available"])

    saved = RegionSelection |> Repo.all() |> Enum.map(& &1.region_name) |> Enum.sort()
    assert saved == ["berlin", "germany"]
  end

  test "POST /admin/regions.json replaces previous selection", %{conn: conn} do
    Repo.insert!(%RegionSelection{region_name: "stale", active: true, position: 0})

    body = %{"selected" => ["berlin"]}

    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/admin/regions.json", Jason.encode!(body))
    |> json_response(200)

    names = RegionSelection |> Repo.all() |> Enum.map(& &1.region_name)
    assert "stale" not in names
    assert "berlin" in names
  end

  test "POST /admin/regions.json broadcasts {:regions_changed, names}", %{conn: conn} do
    Phoenix.PubSub.subscribe(Atlas.PubSub, "admin:regions")

    body = %{"selected" => ["berlin"]}

    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/admin/regions.json", Jason.encode!(body))
    |> json_response(200)

    assert_receive {:regions_changed, ["berlin"]}, 500
  end

  test "POST /admin/regions.json with non-list selected returns 422", %{conn: conn} do
    body = %{"selected" => "berlin"}

    resp =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/admin/regions.json", Jason.encode!(body))
      |> json_response(422)

    assert resp["error"]["code"] == "BAD_REQUEST"
  end
end
