defmodule Atlas.Control.Osmium do
  @moduledoc """
  Wraps native `osmium-tool` invocations through a single GenServer so two
  merges never run concurrently against the same data dir.

  The binary is installed in the release image; all paths are container-local
  (no docker-run indirection, no host-path translation).

  Production passes a `System.cmd/3`-shaped runner; tests inject a stub.
  """

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Merge `sources` (paths relative to `data_dir`) into `out` (also relative).

  Equivalent to running `osmium merge <sources...> -O -o <out>` from `data_dir`.
  Returns `{:ok, output}` or `{:error, exit_code, output}`.
  """
  def merge(data_dir, sources, out) when is_list(sources) do
    # `-f pbf` is not redundant: osmium infers the format from the output
    # extension, and the applier merges to `current.osm.pbf.partial` so an
    # interrupted run leaves a file sweep_partials/1 can recognise and clear.
    # Without an explicit format osmium rejects that name outright and every
    # multi-region apply dies at the merge step.
    args = ["merge"] ++ sources ++ ["-O", "-f", "pbf", "-o", out]
    GenServer.call(__MODULE__, {:osmium, data_dir, args}, call_timeout())
  end

  @doc """
  Convert a PBF file to OSM-XML+bzip2 (required by overpass-api).
  Both paths are relative to `data_dir`.
  """
  def convert_to_osm_bz2(data_dir, in_path, out_path) do
    args = ["cat", in_path, "-o", out_path, "-O", "-f", "osm.bz2"]
    GenServer.call(__MODULE__, {:osmium, data_dir, args}, call_timeout())
  end

  @doc """
  Client-side ceiling for an osmium invocation. Defaults to `:infinity`.

  These are long-running external ports: bzip2 compression is effectively
  single-threaded, so a country-scale `osmium cat -f osm.bz2` runs well past
  an hour. A wall-clock ceiling kills it mid-write and strands a `.partial`,
  so serialization — not a deadline — is what this GenServer is for.
  """
  def call_timeout, do: Application.get_env(:atlas, :osmium_timeout, :infinity)

  @impl true
  def init(opts) do
    {:ok,
     %{
       runner: Keyword.get(opts, :runner, &default_runner/3),
       command: Keyword.get(opts, :command, "osmium"),
       stall_timeout: Keyword.get(opts, :stall_timeout, stall_timeout()),
       stall_poll: Keyword.get(opts, :stall_poll, :timer.seconds(30))
     }}
  end

  @impl true
  def handle_call({:osmium, data_dir, args}, _from, state) do
    owner = self()

    task =
      Task.async(fn ->
        state.runner.(state.command, args, cd: data_dir, stderr_to_stdout: true, report_to: owner)
      end)

    reply =
      case await_with_watchdog(task, output_path(data_dir, args), state) do
        {:ok, {output, 0}} -> {:ok, output}
        {:ok, {output, code}} -> {:error, code, output}
        {:error, :stalled, detail} -> {:error, :stalled, detail}
      end

    flush_os_pid()
    {:reply, reply, state}
  end

  # osmium writes its output file steadily, so "the file stopped growing" is a
  # far better death signal than a wall-clock deadline: a legitimately slow
  # convert keeps growing for hours, while a wedged one flatlines immediately.
  defp await_with_watchdog(task, out_path, state) do
    do_await(task, out_path, state, size_of(out_path), 0)
  end

  defp do_await(task, out_path, state, last_size, stalled_for) do
    case Task.yield(task, state.stall_poll) do
      {:ok, result} ->
        {:ok, result}

      nil ->
        size = size_of(out_path)

        cond do
          size > last_size ->
            do_await(task, out_path, state, size, 0)

          stalled_for + state.stall_poll >= state.stall_timeout ->
            terminate_stalled(task, out_path, state)

          true ->
            do_await(task, out_path, state, size, stalled_for + state.stall_poll)
        end
    end
  end

  defp terminate_stalled(task, out_path, state) do
    # Kill the OS process FIRST: tearing down the Task only drops the port
    # owner, leaving osmium alive to keep writing into the data dir while the
    # freed GenServer lets the next apply start a second one.
    killed? = kill_os_process()

    case {killed?, Task.shutdown(task, :brutal_kill)} do
      # Nothing was killed and it finished inside the race window — honour the
      # real result rather than discarding a completed multi-hour convert.
      {false, {:ok, result}} ->
        {:ok, result}

      # If we SIGKILLed it, the task's own result is just the signal exit (137)
      # racing us back. Report the stall we diagnosed, not the wound we caused.
      _ ->
        {:error, :stalled,
         "no progress on #{out_path} for #{div(state.stall_timeout, 1000)}s — killed"}
    end
  end

  defp size_of(nil), do: 0

  defp size_of(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      {:error, _} -> 0
    end
  end

  # Both `merge` and `cat` name their destination right after `-o`.
  defp output_path(data_dir, args) do
    case Enum.drop_while(args, &(&1 != "-o")) do
      ["-o", out | _] -> Path.expand(out, data_dir)
      _ -> nil
    end
  end

  @doc """
  How long the output file may stop growing before the invocation is killed.
  Defaults to 30 minutes; override with `:osmium_stall_timeout`.
  """
  def stall_timeout,
    do: Application.get_env(:atlas, :osmium_stall_timeout, :timer.minutes(30))

  defp default_runner(cmd, args, opts), do: spawn_and_collect(cmd, args, opts)

  @doc """
  Run `cmd` through a port and block until it exits, returning
  `{output, exit_status}` like `System.cmd/3`.

  A port rather than `System.cmd/3` because the OS pid is knowable that way:
  `System.cmd/3` gives no handle on the child, and tearing down the calling
  process leaves it running. When `:report_to` is a pid it receives
  `{:osmium_os_pid, os_pid}`, which is what lets the stall watchdog kill it.
  """
  def spawn_and_collect(cmd, args, opts) do
    executable = System.find_executable(cmd) || cmd

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :hide,
        args: args,
        cd: Keyword.fetch!(opts, :cd)
      ])

    with pid when is_pid(pid) <- opts[:report_to],
         {:os_pid, os_pid} <- Port.info(port, :os_pid) do
      send(pid, {:osmium_os_pid, os_pid})
    end

    collect_port(port, [])
  end

  defp collect_port(port, acc) do
    receive do
      {^port, {:data, chunk}} -> collect_port(port, [acc | chunk])
      {^port, {:exit_status, status}} -> {IO.iodata_to_binary(acc), status}
    end
  end

  # Through `sh -c` on purpose: `System.cmd/3` execs directly, and the runner
  # image (debian-slim) has no `kill` binary — that lives in procps, which is
  # not installed. `kill` is a shell builtin, so this works with no new
  # dependency. Failures are swallowed: losing the child is bad, but crashing
  # this GenServer is worse, since it sits under :rest_for_one and would take
  # the applier and the service supervisors down mid-apply.
  # Returns true when a child was actually signalled.
  defp kill_os_process do
    receive do
      {:osmium_os_pid, os_pid} ->
        System.cmd("/bin/sh", ["-c", "kill -9 #{os_pid}"], stderr_to_stdout: true)
        true
    after
      0 -> false
    end
  rescue
    e ->
      Logger.warning("could not kill stalled osmium: #{Exception.message(e)}")
      true
  end

  defp flush_os_pid do
    receive do
      {:osmium_os_pid, _} -> flush_os_pid()
    after
      0 -> :ok
    end
  end
end
