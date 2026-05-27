defmodule AtlasWeb.Plugs.AdminAuthTest do
  use AtlasWeb.ConnCase, async: false

  setup do
    System.put_env("ADMIN_USERNAME", "admin")
    System.put_env("ADMIN_PASSWORD", "s3cret")

    on_exit(fn ->
      Enum.each(~w[ADMIN_USERNAME ADMIN_PASSWORD], &System.delete_env/1)
    end)

    :ok
  end

  test "GET /admin/services returns 401 without basic auth", %{conn: conn} do
    conn = get(conn, "/admin/services")
    assert response(conn, 401)
    assert get_resp_header(conn, "www-authenticate") |> List.first() =~ "Basic"
  end

  test "GET /admin/services returns 401 with wrong creds", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Basic " <> Base.encode64("admin:wrong"))
      |> get("/admin/services")

    assert response(conn, 401)
  end

  test "GET /admin/services passes with correct creds", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Basic " <> Base.encode64("admin:s3cret"))
      |> get("/admin/services")

    # Auth passed → status is no longer 401. The exact body comes from the
    # PlaceholderLive until the real ServicesLive lands in Task 6.
    refute conn.status == 401
  end

  test "GET /admin/services returns 503 when env vars unset", %{conn: conn} do
    System.delete_env("ADMIN_USERNAME")
    System.delete_env("ADMIN_PASSWORD")

    conn = get(conn, "/admin/services")
    assert response(conn, 503) =~ "Admin panel unconfigured"
  end
end
