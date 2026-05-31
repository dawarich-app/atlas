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

  test "missing_param/2 returns 400 with MISSING_PARAM + details.param", %{conn: conn} do
    conn = BaseController.missing_param(conn, "q")
    assert conn.status == 400
    body = Jason.decode!(conn.resp_body)
    assert body["error"]["code"] == "MISSING_PARAM"
    assert body["error"]["message"] == "q is required"
    assert body["error"]["details"]["param"] == "q"
  end

  test "validation_error/2 returns 422 with VALIDATION_ERROR and no details key when details empty", %{conn: conn} do
    conn = BaseController.validation_error(conn, "lat must be numeric")
    assert conn.status == 422
    body = Jason.decode!(conn.resp_body)
    assert body["error"]["code"] == "VALIDATION_ERROR"
    assert body["error"]["message"] == "lat must be numeric"
    refute Map.has_key?(body["error"], "details")
  end

  test "validation_error/3 returns 422 with details", %{conn: conn} do
    conn = BaseController.validation_error(conn, "too many items, max 500", %{max: 500})
    assert conn.status == 422
    body = Jason.decode!(conn.resp_body)
    assert body["error"]["code"] == "VALIDATION_ERROR"
    assert body["error"]["details"]["max"] == 500
  end

  test "parse_float_required/1 returns {:ok, float} or {:error, :invalid_float}" do
    assert {:ok, 1.5} = BaseController.parse_float_required("1.5")
    assert {:ok, 2.0} = BaseController.parse_float_required(2)
    assert {:error, :invalid_float} = BaseController.parse_float_required("abc")
    assert {:error, :invalid_float} = BaseController.parse_float_required(nil)
  end

  test "parse_bbox_required/1 returns {:ok, bbox} or {:error, :invalid_bbox}" do
    assert {:ok, [13.0, 52.0, 14.0, 53.0]} = BaseController.parse_bbox_required("13.0,52.0,14.0,53.0")
    assert {:error, :invalid_bbox} = BaseController.parse_bbox_required("garbage")
    assert {:error, :invalid_bbox} = BaseController.parse_bbox_required(nil)
  end
end
