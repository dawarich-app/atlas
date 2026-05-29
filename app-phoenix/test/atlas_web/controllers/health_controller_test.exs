defmodule AtlasWeb.HealthControllerTest do
  use AtlasWeb.ConnCase, async: true

  test "GET /up returns 200 and ok body", %{conn: conn} do
    conn = get(conn, ~p"/up")
    assert response(conn, 200) == "ok"
  end
end
