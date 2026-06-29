defmodule Atlas.Control.Osmium do
  @moduledoc """
  Wraps native `osmium-tool` invocations through a single GenServer so two
  merges never run concurrently against the same data dir.

  The binary is installed in the release image; all paths are container-local
  (no docker-run indirection, no host-path translation).

  Production passes a `System.cmd/3`-shaped runner; tests inject a stub.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Merge `sources` (paths relative to `data_dir`) into `out` (also relative).

  Equivalent to running `osmium merge <sources...> -O -o <out>` from `data_dir`.
  Returns `{:ok, output}` or `{:error, exit_code, output}`.
  """
  def merge(data_dir, sources, out) when is_list(sources) do
    args = ["merge"] ++ sources ++ ["-O", "-o", out]
    GenServer.call(__MODULE__, {:osmium, data_dir, args}, :timer.minutes(30))
  end

  @doc """
  Convert a PBF file to OSM-XML+bzip2 (required by overpass-api).
  Both paths are relative to `data_dir`.
  """
  def convert_to_osm_bz2(data_dir, in_path, out_path) do
    args = ["cat", in_path, "-o", out_path, "-O", "-f", "osm.bz2"]
    GenServer.call(__MODULE__, {:osmium, data_dir, args}, :timer.minutes(30))
  end

  @impl true
  def init(opts) do
    runner = Keyword.get(opts, :runner, &default_runner/3)
    {:ok, %{runner: runner}}
  end

  @impl true
  def handle_call({:osmium, data_dir, args}, _from, %{runner: runner} = state) do
    reply =
      case runner.("osmium", args, cd: data_dir, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {output, code} -> {:error, code, output}
      end

    {:reply, reply, state}
  end

  defp default_runner(cmd, args, opts), do: System.cmd(cmd, args, opts)
end
