defmodule Atlas.Control.OsmiumTest do
  use ExUnit.Case, async: false
  alias Atlas.Control.Osmium

  # True once no process matches `pattern`. pgrep is exec'd directly, NOT via
  # `sh -c`: a wrapper shell's own argv would contain the pattern, and Linux
  # procps pgrep matches its ancestors (BSD pgrep excludes them, so that form
  # passes on macOS and is permanently red on CI). Exit status 1 = no match.
  defp wait_until_gone(pattern, attempts \\ 100) do
    case System.cmd("pgrep", ["-f", pattern], stderr_to_stdout: true) do
      {_, 1} ->
        true

      _ when attempts > 0 ->
        Process.sleep(50)
        wait_until_gone(pattern, attempts - 1)

      _ ->
        false
    end
  end

  defp start_osmium(result) do
    test_pid = self()

    runner = fn cmd, args, opts ->
      send(test_pid, {:stub, cmd, args, opts})
      result
    end

    start_supervised!({Osmium, runner: runner})
  end

  test "merge/3 invokes native osmium merge inside data_dir" do
    start_osmium({"ok", 0})

    assert {:ok, "ok"} =
             Osmium.merge(
               "/work/data/osm/sources",
               ["a.osm.pbf", "b.osm.pbf"],
               "../merged.osm.pbf"
             )

    assert_received {:stub, "osmium", args, opts}

    assert args == [
             "merge",
             "a.osm.pbf",
             "b.osm.pbf",
             "-O",
             "-f",
             "pbf",
             "-o",
             "../merged.osm.pbf"
           ]

    assert opts[:cd] == "/work/data/osm/sources"
    assert opts[:stderr_to_stdout] == true
  end

  test "convert_to_osm_bz2/3 invokes native osmium cat with osm.bz2 format" do
    start_osmium({"ok", 0})

    assert {:ok, "ok"} = Osmium.convert_to_osm_bz2("/work/data/osm", "in.osm.pbf", "out.osm.bz2")

    assert_received {:stub, "osmium", args, opts}

    assert args == ["cat", "in.osm.pbf", "-o", "out.osm.bz2", "-O", "-f", "osm.bz2"]
    assert opts[:cd] == "/work/data/osm"
  end

  test "merge/3 names the output format, so a .partial destination still works" do
    # osmium infers the format from the output extension and refuses anything
    # it does not recognise ("Could not detect file format for filename
    # '../current.osm.pbf.partial'"). The applier writes to a .partial and
    # renames on success — that suffix is what sweep_partials/1 uses to clear
    # orphans from an interrupted run — so the format has to be explicit.
    # convert_to_osm_bz2/3 already does this; merge/3 did not, which meant
    # multi-region applies failed at the merge step every time.
    start_osmium({"ok", 0})

    assert {:ok, "ok"} =
             Osmium.merge("/work/data/osm/sources", ["a.osm.pbf"], "../current.osm.pbf.partial")

    assert_received {:stub, "osmium", args, _opts}
    assert ["-f", "pbf"] == Enum.slice(args, Enum.find_index(args, &(&1 == "-f")), 2)
  end

  test "non-zero exit returns error with code and output" do
    start_osmium({"Open failed for 'a.osm.pbf'", 1})

    assert {:error, 1, "Open failed for 'a.osm.pbf'"} =
             Osmium.merge("/work/data/osm/sources", ["a.osm.pbf"], "out.osm.pbf")
  end

  describe "call timeout" do
    test "defaults to :infinity so a slow convert is never killed by wall clock" do
      assert Osmium.call_timeout() == :infinity
    end

    test "a convert far longer than the old 30-minute ceiling still succeeds" do
      # bzip2 compression of a country-scale PBF runs 45-50 min; the previous
      # hard-coded :timer.minutes(30) killed it mid-write.
      slow_runner = fn _cmd, _args, _opts ->
        Process.sleep(120)
        {"done", 0}
      end

      start_supervised!({Osmium, runner: slow_runner})

      assert {:ok, "done"} =
               Osmium.convert_to_osm_bz2("/work/data/osm", "current.osm.pbf", "out.partial")
    end

    test "a stalled convert is killed even though the call timeout is :infinity" do
      # :infinity is right for a SLOW convert (bzip2 on a planet extract runs
      # for hours). A HUNG one is different: without a stall check the GenServer
      # is wedged forever and every later apply gets {:error, :busy}.
      tmp = Path.join(System.tmp_dir!(), "osmium-stall-#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      hung_runner = fn _cmd, _args, _opts ->
        Process.sleep(30_000)
        {"never gets here", 0}
      end

      start_supervised!({Osmium, runner: hung_runner, stall_timeout: 1_000, stall_poll: 200})

      assert {:error, :stalled, msg} =
               Osmium.convert_to_osm_bz2(tmp, "current.osm.pbf", "out.partial")

      assert msg =~ "no progress"
    end

    test "a slow but progressing convert is not killed by the stall watchdog" do
      tmp = Path.join(System.tmp_dir!(), "osmium-slow-#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      out = Path.join(tmp, "out.partial")

      growing_runner = fn _cmd, _args, _opts ->
        Enum.each(1..20, fn n ->
          File.write!(out, String.duplicate("x", n * 1000))
          Process.sleep(100)
        end)

        {"done", 0}
      end

      # The run (~2s) deliberately outlives the 1.5s no-growth tolerance, so a
      # pass proves growth RESETS the stall counter rather than proving the
      # convert simply finished first. The write interval (100ms) sits far
      # under the tolerance, so it survives a heavily loaded runner: growth has
      # to go unobserved for 1.5s straight before anything is killed.
      start_supervised!({Osmium, runner: growing_runner, stall_timeout: 1_500, stall_poll: 200})

      assert {:ok, "done"} = Osmium.convert_to_osm_bz2(tmp, "current.osm.pbf", "out.partial")
    end

    test "the stall watchdog kills the real OS process, not just the Elixir task" do
      # Task.shutdown/2 tears down the wrapper only; the port's child survives.
      # If osmium outlives the "killed" reply it keeps writing to the data dir
      # while the freed GenServer lets the next apply start a second one.
      tmp = Path.join(System.tmp_dir!(), "osmium-kill-#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      # The duration IS the marker: it lands in the child's own argv, so pgrep
      # can see it. A trailing comment would not — `exec` replaces the shell and
      # the comment never reaches argv, which makes the pgrep assertion pass
      # whether or not the child was actually killed.
      #
      # It has to be unique across RUNS, not just within one: should this test
      # ever leak a child, that process sleeps for an hour and a narrow marker
      # range would make every later run collide with the orphan and fail. The
      # uniqueness rides in the fraction — concatenating pid and counter into
      # the whole-seconds part overflows what `sleep` accepts.
      marker = "3600.#{List.to_string(:os.getpid())}#{System.unique_integer([:positive])}"

      # Belt and braces: never leak a multi-hour sleep, even if we fail early.
      on_exit(fn -> System.cmd("pkill", ["-f", "sleep #{marker}"], stderr_to_stdout: true) end)

      # The real port-spawning runner, just pointed at `sleep` so the test does
      # not need osmium installed.
      port_runner = fn _cmd, _args, opts ->
        Osmium.spawn_and_collect("sleep", ["#{marker}"], opts)
      end

      # Generous on purpose. The watchdog must not reach its deadline before the
      # Task has even been scheduled and the port opened — otherwise there is no
      # pid to kill yet and the test fails for a reason that says nothing about
      # the behaviour under test. A loaded CI runner makes tight values a
      # coin flip.
      start_supervised!({Osmium, runner: port_runner, stall_timeout: 1_000, stall_poll: 200})

      assert {:error, :stalled, _} =
               Osmium.convert_to_osm_bz2(tmp, "current.osm.pbf", "out.partial")

      # Poll rather than sleeping a fixed span: reaping a SIGKILLed process is
      # not instantaneous, and on a loaded runner a fixed wait is a coin flip.
      assert wait_until_gone("sleep #{marker}"),
             "the child must be dead once we report it killed — otherwise it keeps " <>
               "writing to the data dir while the freed GenServer admits a second run"
    end

    test "spawn_and_collect reports the OS pid and returns output with the exit status" do
      # The child has to outlive the Port.info/2 call: a process that exits
      # immediately can close the port first, and Port.info then returns nil so
      # no pid is ever reported. Harmless in production — a stalled osmium has
      # been running for half an hour by the time the watchdog asks — but on a
      # loaded CI runner `echo` alone is fast enough to lose the race.
      assert {"hello\n", 0} =
               Osmium.spawn_and_collect("sh", ["-c", "sleep 0.2; echo hello"],
                 cd: File.cwd!(),
                 report_to: self()
               )

      assert_received {:osmium_os_pid, os_pid} when is_integer(os_pid)

      assert {"", 3} = Osmium.spawn_and_collect("sh", ["-c", "exit 3"], cd: File.cwd!())
    end

    test "an explicit timeout override is honoured" do
      Application.put_env(:atlas, :osmium_timeout, 20)
      on_exit(fn -> Application.delete_env(:atlas, :osmium_timeout) end)

      assert Osmium.call_timeout() == 20

      blocking_runner = fn _cmd, _args, _opts ->
        Process.sleep(500)
        {"done", 0}
      end

      start_supervised!({Osmium, runner: blocking_runner})

      assert catch_exit(
               Osmium.convert_to_osm_bz2("/work/data/osm", "current.osm.pbf", "out.partial")
             )
    end
  end
end
