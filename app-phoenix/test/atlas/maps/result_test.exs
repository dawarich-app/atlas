defmodule Atlas.Maps.ResultTest do
  use ExUnit.Case, async: true
  alias Atlas.Maps.Result

  test "constructs with features and upstream_status" do
    r = %Result{features: [%{id: "1"}], upstream_status: "ok"}
    assert r.features == [%{id: "1"}]
    assert r.upstream_status == "ok"
  end

  test "defaults features to empty list and upstream_status to ok" do
    r = %Result{}
    assert r.features == []
    assert r.upstream_status == "ok"
  end
end
