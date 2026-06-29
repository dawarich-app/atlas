defmodule Atlas.Control.RegionSelectionTest do
  use Atlas.DataCase, async: false

  alias Atlas.Control.RegionSelection

  test "toggle/1 adds, then removes a region" do
    RegionSelection.toggle("berlin")
    assert RegionSelection.active_names() == ["berlin"]

    RegionSelection.toggle("berlin")
    assert RegionSelection.active_names() == []
  end

  test "clear/0 removes every selection" do
    RegionSelection.toggle("berlin")
    RegionSelection.toggle("bayern")
    assert length(RegionSelection.active_names()) == 2

    RegionSelection.clear()
    assert RegionSelection.active_names() == []
  end

  test "pending_change?/0 is false right after mark_applied! and true after edits" do
    RegionSelection.toggle("berlin")
    assert RegionSelection.pending_change?()

    RegionSelection.mark_applied!()
    refute RegionSelection.pending_change?()

    RegionSelection.toggle("bayern")
    assert RegionSelection.pending_change?()

    RegionSelection.toggle("bayern")
    refute RegionSelection.pending_change?()
  end
end
