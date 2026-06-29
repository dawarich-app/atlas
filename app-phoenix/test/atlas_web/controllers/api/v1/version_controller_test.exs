defmodule AtlasWeb.Api.V1.VersionControllerTest do
  use AtlasWeb.ConnCase, async: false

  test "GET /api/v1/version returns version and revision", %{conn: conn} do
    System.put_env("APP_REVISION", "abc1234def")
    on_exit(fn -> System.delete_env("APP_REVISION") end)

    body =
      conn
      |> get(~p"/api/v1/version")
      |> json_response(200)

    assert body["data"]["version"] == Atlas.Version.version()
    assert body["data"]["revision"] == "abc1234"
  end

  test "revision is null outside a release build", %{conn: conn} do
    System.delete_env("APP_REVISION")

    body =
      conn
      |> get(~p"/api/v1/version")
      |> json_response(200)

    assert body["data"]["revision"] == nil
  end
end
