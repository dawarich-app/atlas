defmodule AtlasWeb.Api.V1.BaseControllerTest do
  use AtlasWeb.ConnCase, async: true
  alias AtlasWeb.Api.V1.BaseController

  test "meta/2 returns {timestamp: ISO8601, ...extras}", %{conn: conn} do
    meta = BaseController.meta(conn, upstream: "ok", count: 5)
    assert {:ok, _, _} = DateTime.from_iso8601(meta.timestamp)
    assert meta.upstream == "ok"
    assert meta.count == 5
    refute Map.has_key?(meta, :request_id)
  end

  test "meta/1 returns timestamp only", %{conn: conn} do
    meta = BaseController.meta(conn)
    assert {:ok, _, _} = DateTime.from_iso8601(meta.timestamp)
    refute Map.has_key?(meta, :request_id)
  end
end
