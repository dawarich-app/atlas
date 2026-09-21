defmodule Atlas.Control.ApplyLogTest do
  use ExUnit.Case, async: false

  alias Atlas.Control.ApplyLog

  setup do
    start_supervised!(ApplyLog)
    Phoenix.PubSub.subscribe(Atlas.PubSub, ApplyLog.topic())
    :ok
  end

  test "appended lines are timestamped, broadcast, and replayed oldest first" do
    ApplyLog.append("first")
    ApplyLog.append("second")

    assert_receive {:log_line, first}
    assert first =~ ~r/^\d{2}:\d{2}:\d{2} first$/
    assert_receive {:log_line, _second}

    assert [^first, second] = ApplyLog.recent()
    assert second =~ ~r/second$/
  end

  test "clear drops the previous run's lines" do
    ApplyLog.append("old run")
    ApplyLog.clear()
    ApplyLog.append("new run")

    assert [line] = ApplyLog.recent()
    assert line =~ "new run"
  end

  test "keeps only the most recent 500 lines" do
    for n <- 1..501, do: ApplyLog.append("line #{n}")

    lines = ApplyLog.recent()
    assert length(lines) == 500
    assert hd(lines) =~ ~r/ line 2$/
    assert List.last(lines) =~ ~r/ line 501$/
  end
end
