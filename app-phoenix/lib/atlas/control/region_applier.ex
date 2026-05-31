defmodule Atlas.Control.RegionApplier do
  @moduledoc """
  Serializes the "apply selected regions" workflow: locate the PBF for each
  region, hand them off to `Atlas.Control.Osmium` for a single `osmium merge`
  run, and broadcast progress on `"control:apply:<job_id>"`.

  The merge invocation is wrapped via a `:runner` function so tests can run
  end-to-end without an actual `osmium-tool` binary. Production passes the
  default runner that calls `Atlas.Control.Osmium.merge/3`.

  PBF lookup is injected at start-up via the `:pbf_lookup` option (a function
  taking a region name and returning a path relative to `:data_dir`). The
  default just appends `.osm.pbf`. Tests inject their own lookup.
  """

  use GenServer

  defstruct [:runner, :pbf_lookup, :data_dir, :output_path, current: nil]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start applying the given list of region names. Returns `{:ok, job_id}`
  immediately; the actual merge runs in a `Task` so the GenServer stays
  free to accept new requests. Progress is broadcast on
  `"control:apply:<job_id>"`.
  """
  def start(regions) when is_list(regions) do
    GenServer.call(__MODULE__, {:apply, regions})
  end

  @doc """
  Project disk usage + service intents for a set of regions and proposed
  service-enable changes — without running osmium. Mirrors Rails
  `ApplyProjection.summary`.

  ## Returns

      %{
        total_disk_gb: float,
        first_boot_hours: float,
        lines: [%{name: String.t(), disk_gb: float, hours: float}],
        service_intents: [%{name: String.t(), enabled: boolean, reason: String.t()}]
      }
  """
  def project(regions, intents \\ []) when is_list(regions) and is_list(intents) do
    Atlas.Control.ApplyProjection.summary(regions, intents)
  end

  @doc "Inspect current applier state — `nil` when idle."
  def status, do: GenServer.call(__MODULE__, :status)

  @doc "PubSub topic for a given job id."
  def topic(job_id), do: "control:apply:#{job_id}"

  @impl true
  def init(opts) do
    state = %__MODULE__{
      runner: Keyword.get(opts, :runner, &default_runner/3),
      pbf_lookup: Keyword.get(opts, :pbf_lookup, &default_pbf_lookup/1),
      data_dir: Keyword.get(opts, :data_dir, "/data"),
      output_path: Keyword.get(opts, :output_path, "regions.osm.pbf")
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:apply, regions}, _from, state) do
    job_id = Ecto.UUID.generate()
    broadcast(job_id, {:apply_start, job_id, regions})

    sources = Enum.map(regions, state.pbf_lookup)

    parent = self()

    Task.start(fn ->
      result = state.runner.(state.data_dir, sources, state.output_path)

      case result do
        :ok ->
          broadcast(job_id, {:apply_done, job_id, regions})

        {:error, reason} ->
          broadcast(job_id, {:apply_error, job_id, reason})

        {0, _output} ->
          broadcast(job_id, {:apply_done, job_id, regions})

        {code, output} when is_integer(code) ->
          broadcast(job_id, {:apply_error, job_id, {code, output}})
      end

      send(parent, {:applier_done, job_id})
    end)

    {:reply, {:ok, job_id}, %{state | current: %{job_id: job_id, regions: regions}}}
  end

  def handle_call(:status, _from, state), do: {:reply, state.current, state}

  @impl true
  def handle_info({:applier_done, _job_id}, state) do
    {:noreply, %{state | current: nil}}
  end

  defp broadcast(job_id, msg), do: Phoenix.PubSub.broadcast(Atlas.PubSub, topic(job_id), msg)

  defp default_runner(data_dir, sources, output_path) do
    Atlas.Control.Osmium.merge(data_dir, sources, output_path)
  end

  defp default_pbf_lookup(region), do: "#{region}.osm.pbf"
end
