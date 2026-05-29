defmodule Atlas.Control.Parsers.LibpostalTest do
  use ExUnit.Case, async: true

  alias Atlas.Control.Parsers.Libpostal
  alias Atlas.Control.Parsers.LogReplay

  describe "Libpostal parser (log-fixture replay)" do
    test "ready fixture yields phase=ready, ready=true, progress=1.0" do
      result = LogReplay.replay(Libpostal, LogReplay.fixture("libpostal-ready.log"))

      assert result.phase == "ready"
      assert result.ready
      assert result.progress == 1.0
    end
  end
end
