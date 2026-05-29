defmodule Atlas.Control.Osmium do
  @moduledoc """
  Wraps `osmium-tool` invocations (via a docker container) through a single
  GenServer so two merges never run concurrently against the same data dir.

  Production passes `&System.cmd/2` as the runner; tests inject a stub.
  Mirrors `internal/osmium/osmium.go` from the Go sidecar.
  """

  use GenServer

  @image "stefda/osmium-tool"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Merge `sources` (paths relative to `data_dir`) into `out` (also relative).

  Equivalent to:

      docker run --rm -v <data_dir>:/data -w /data stefda/osmium-tool \
        osmium merge <sources...> -O -o <out>
  """
  def merge(data_dir, sources, out) when is_list(sources) do
    args =
      ["run", "--rm", "-v", "#{data_dir}:/data", "-w", "/data", @image, "osmium", "merge"] ++
        sources ++ ["-O", "-o", out]

    GenServer.call(__MODULE__, {:docker, args}, :timer.minutes(30))
  end

  @doc """
  Convert a PBF file to OSM-XML+bzip2 (required by overpass-api).
  Both paths are relative to `data_dir`.
  """
  def convert_to_osm_bz2(data_dir, in_path, out_path) do
    args = [
      "run", "--rm", "-v", "#{data_dir}:/data", "-w", "/data", @image,
      "osmium", "cat", in_path, "-o", out_path, "-O", "-f", "osm.bz2"
    ]

    GenServer.call(__MODULE__, {:docker, args}, :timer.minutes(30))
  end

  @impl true
  def init(opts) do
    runner = Keyword.get(opts, :runner, &System.cmd/2)
    {:ok, %{runner: runner}}
  end

  @impl true
  def handle_call({:docker, args}, _from, %{runner: runner} = state) do
    {output, exit_code} = runner.("docker", args)
    {:reply, {exit_code, output}, state}
  end
end
