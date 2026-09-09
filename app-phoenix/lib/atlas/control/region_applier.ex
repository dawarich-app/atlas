defmodule Atlas.Control.RegionApplier do
  @moduledoc """
  Serializes the "apply selected regions" workflow, mirroring the Go sidecar's
  `runApplyRegions` (atlas-control/internal/server/server.go) stage for stage:

    1. download PBFs into `osm/sources/` and GTFS into `gtfs/` using a shared
       pool of up to three downloads (skip when present)
    2. wait for all downloads; GTFS failures are non-fatal
    3. materialise `osm/current.osm.pbf` — relative symlink for one source,
       `osmium merge` via `.partial` + rename for several
    4. stage OTP inputs (`otp/region.osm.pbf` + GTFS zips, drop `graph.obj`)
    5. convert to `osm/current.osm.bz2` for overpass — last, because it only
       feeds overpass and can run for hours. Failure is fatal to the apply (a
       swallowed one would leave overpass importing a stale snapshot silently)
       but the other services still get restarted onto their fresh data.
    6. `docker compose restart` the enabled ingest services

  All paths are container-local under `data_dir` (default `/work/data`) — no
  host-path translation. Every stage broadcasts on the stable topic
  `"control:apply"`:

      {:apply_start,      %{job_id, regions}}
      {:apply_progress,   %{job_id, phase, region, progress, item}}
      {:apply_restarting, [service_name]}
      {:apply_error,      %{job_id, phase, reason}}
      {:apply_done,       %{job_id, regions}}

  `:item` is present only on `:downloading` and names one file
  (`%{label, source, current, total}`). `{:apply_restarting, names}` carries
  exactly the ingest services this run hands its fresh data to — a failed
  Overpass conversion omits `"overpass"` — so the timeline can say which
  sidecar was left behind, and why.

  `status/0` returns the running job, the last failed job (so a page refresh
  can still show what broke), or `nil`.

  Collaborators (downloader, osmium, restart, catalog lookup) are injected at
  start-up so tests run without network, osmium, or docker.
  """

  use GenServer

  require Logger

  alias Atlas.Control.{OtpBuildConfig, TransitSourceFiles, TransitSources}

  @topic "control:apply"
  @ingest_services ~w(valhalla overpass)

  defstruct [
    :downloader,
    :osmium_merge,
    :osmium_convert,
    :restart,
    :enabled?,
    :catalog_find,
    :data_dir,
    services: nil,
    transit_sources: nil,
    transit_only: false,
    current: nil,
    last_failure: nil
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start applying the given list of region names. Region names are validated
  against the catalog upfront. Returns `{:ok, job_id}`, or
  `{:error, {:region_not_found, name}}` / `{:error, :busy}` without starting
  a job. The pipeline runs in a `Task`; progress arrives on `topic/0`.
  """
  def start(regions, opts \\ []) when is_list(regions) do
    GenServer.call(__MODULE__, {:apply, regions, opts})
  end

  @doc """
  Project disk usage + service intents for a set of regions and proposed
  service-enable changes — without touching any data.
  """
  def project(regions, intents \\ []) when is_list(regions) and is_list(intents) do
    Atlas.Control.ApplyProjection.summary(regions, intents)
  end

  @doc """
  Current applier state: `%{job_id, regions, phase, region, progress}` while
  a job runs, `%{job_id, regions, phase, error}` after a failure (until the
  next job starts), `nil` otherwise.
  """
  def status, do: GenServer.call(__MODULE__, :status)

  @doc "Stable PubSub topic carrying all apply lifecycle events."
  def topic, do: @topic

  @impl true
  def init(opts) do
    state = %__MODULE__{
      downloader: Keyword.get(opts, :downloader, &Atlas.Control.Downloader.fetch/3),
      osmium_merge: Keyword.get(opts, :osmium_merge, &Atlas.Control.Osmium.merge/3),
      osmium_convert:
        Keyword.get(opts, :osmium_convert, &Atlas.Control.Osmium.convert_to_osm_bz2/3),
      restart: Keyword.get(opts, :restart, &default_restart/1),
      enabled?: Keyword.get(opts, :enabled?, &default_enabled?/1),
      catalog_find: Keyword.get(opts, :catalog_find, &Atlas.Control.RegionCatalog.find/1),
      data_dir: Keyword.get(opts, :data_dir, "/work/data")
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:apply, regions, opts}, _from, state) do
    cond do
      state.current != nil ->
        {:reply, {:error, :busy}, state}

      missing = Enum.find(regions, &is_nil(state.catalog_find.(&1))) ->
        {:reply, {:error, {:region_not_found, missing}}, state}

      true ->
        job_id = Ecto.UUID.generate()
        entries = Enum.map(regions, state.catalog_find)
        broadcast({:apply_start, %{job_id: job_id, regions: regions}})
        Logger.info("region apply started: #{Enum.join(regions, ", ")} (job #{job_id})")

        sources = if TransitSources.configured?(), do: TransitSources.enabled(), else: nil
        parent = self()

        Task.start(fn ->
          result =
            try do
              run_pipeline(
                %{
                  state
                  | services: Keyword.get(opts, :services),
                    transit_sources: sources,
                    transit_only: Keyword.get(opts, :transit_only, false)
                },
                job_id,
                regions,
                entries
              )
            rescue
              e -> {:error, :unexpected, e}
            catch
              :exit, reason -> {:error, :unexpected, {:exit, reason}}
            end

          send(parent, {:applier_done, job_id, regions, result})
        end)

        current = %{job_id: job_id, regions: regions, phase: :downloading, progress: nil}
        {:reply, {:ok, job_id}, %{state | current: current, last_failure: nil}}
    end
  end

  def handle_call(:status, _from, state) do
    {:reply, state.current || state.last_failure, state}
  end

  @impl true
  def handle_info({:applier_done, job_id, regions, result}, state) do
    case result do
      :ok ->
        broadcast({:apply_done, %{job_id: job_id, regions: regions}})
        Logger.info("region apply finished: #{Enum.join(regions, ", ")}")
        {:noreply, %{state | current: nil, last_failure: nil}}

      {:error, phase, reason} ->
        reason = format_reason(reason)
        broadcast({:apply_error, %{job_id: job_id, phase: phase, reason: reason}})
        Logger.warning("region apply failed during #{phase}: #{reason}")

        failure = %{job_id: job_id, regions: regions, phase: phase, error: reason}
        {:noreply, %{state | current: nil, last_failure: failure}}
    end
  end

  def handle_info({:applier_progress, progress}, state) do
    current = state.current && Map.merge(state.current, progress)
    {:noreply, %{state | current: current}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  ## Pipeline (runs inside the Task)

  defp run_pipeline(%{transit_only: true} = state, job_id, _regions, _entries) do
    :ok = prepare_transit_sources(state, job_id)

    if File.exists?(Path.join(state.data_dir, "otp/region.osm.pbf")) do
      restart_services(state, job_id, [Atlas.Settings.transit_backend()])
    else
      :ok
    end
  end

  defp run_pipeline(state, job_id, _regions, entries) do
    osm_dir = Path.join(state.data_dir, "osm")
    sources_dir = Path.join(osm_dir, "sources")
    gtfs_dir = Path.join(state.data_dir, "gtfs")
    File.mkdir_p!(sources_dir)
    File.mkdir_p!(gtfs_dir)
    Enum.each([osm_dir, sources_dir, gtfs_dir], &sweep_partials/1)

    with {:ok, sources} <- download_sources(state, job_id, entries, sources_dir, gtfs_dir),
         :ok <- materialize_current(state, job_id, osm_dir, sources_dir, sources),
         :ok <-
           for_services(state, ["valhalla"], fn -> stage_valhalla(state, job_id, osm_dir) end),
         :ok <-
           for_services(state, ~w(motis otp), fn ->
             stage_transit(state, job_id, osm_dir, gtfs_dir, entries)
           end),
         :ok <-
           Atlas.Control.ServiceCoverage.record_inputs(state.data_dir, entries, state.services) do
      # Convert last: it only feeds overpass, and it is the one stage that can
      # take hours. Everything valhalla and OTP need is already on disk, so a
      # failed conversion still fails the apply (loudly — see #28) but does not
      # withhold fresh data from the services that are ready for it.
      case convert_for_overpass(state, job_id, osm_dir) do
        :ok ->
          restart_services(state, job_id, @ingest_services ++ [Atlas.Settings.transit_backend()])

        {:error, _phase, _reason} = error ->
          restart_after_failed_convert(state, job_id)
          error
      end
    end
  end

  defp for_services(state, names, fun) do
    if is_nil(state.services) or Enum.any?(names, &(&1 in state.services)), do: fun.(), else: :ok
  end

  # One shared pool for map extracts and timetables. Drain it before returning
  # an error: retries must never race unfinished writers from an earlier job.
  defp download_sources(state, job_id, entries, sources_dir, gtfs_dir) do
    pbfs =
      for entry <- entries,
          url <- entry.pbf_urls,
          do: {:pbf, entry, url, Path.join(sources_dir, Path.basename(url))}

    feeds =
      if is_nil(state.transit_sources) and
           (is_nil(state.services) or Enum.any?(~w(motis otp), &(&1 in state.services))) do
        for entry <- entries,
            entry.gtfs_url not in [nil, ""],
            do:
              {:gtfs, entry, entry.gtfs_url,
               Path.join(gtfs_dir, entry.gtfs_name || Path.basename(entry.gtfs_url))}
      else
        []
      end

    jobs = Enum.uniq_by(pbfs ++ feeds, fn {_, _, url, dest} -> {url, dest} end)
    destinations = Enum.map(jobs, &elem(&1, 3))

    if length(destinations) != length(Enum.uniq(destinations)) do
      {:error, :downloading, "Different sources use the same destination filename"}
    else
      results =
        jobs
        |> Task.async_stream(&download_source(state, job_id, &1),
          max_concurrency: 3,
          timeout: :infinity,
          ordered: true
        )
        |> Enum.to_list()

      collect_downloads(results)
    end
  end

  defp collect_downloads(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, {:ok, :pbf, file}}, {:ok, files} -> {:cont, {:ok, files ++ [file]}}
      {:ok, {:ok, :gtfs, _}}, acc -> {:cont, acc}
      {:ok, {:error, _, _} = error}, _ -> {:halt, error}
      {:exit, reason}, _ -> {:halt, {:error, :downloading, reason}}
    end)
  end

  defp download_source(state, job_id, {kind, entry, url, dest}) do
    report = fn current, total, status ->
      fraction = if total && total > 0, do: current / total, else: nil

      progress(state, job_id, :downloading, %{
        region: entry.name,
        progress: fraction,
        item: %{
          label: Path.basename(dest),
          source: url,
          current: current,
          total: total,
          state: status
        }
      })
    end

    report.(0, nil, :running)

    result =
      fetch_source(state, url, dest, fn current, total -> report.(current, total, :running) end)

    case result do
      {:ok, _} ->
        size =
          case File.stat(dest) do
            {:ok, stat} -> stat.size
            _ -> nil
          end

        report.(size || 0, size, :done)
        {:ok, kind, Path.basename(dest)}

      {:error, reason} ->
        report.(0, nil, :error)
        download_error(kind, url, reason)
    end
  end

  defp fetch_source(state, url, dest, report) do
    state.downloader.(url, dest, report)
  rescue
    error -> {:error, Exception.message(error)}
  catch
    :exit, reason -> {:error, reason}
  end

  defp download_error(:gtfs, url, reason) do
    Logger.warning("timetable download failed: #{url}: #{inspect(reason)}")
    {:ok, :gtfs, nil}
  end

  defp download_error(:pbf, url, reason), do: {:error, :downloading, {url, reason}}

  defp materialize_current(state, job_id, osm_dir, sources_dir, sources) do
    progress(state, job_id, :merging, %{region: nil, progress: nil})
    current = Path.join(osm_dir, "current.osm.pbf")

    case sources do
      [single] ->
        File.rm(current)

        case File.ln_s(Path.join("sources", single), current) do
          :ok -> :ok
          {:error, reason} -> {:error, :merging, {:symlink, reason}}
        end

      many ->
        case state.osmium_merge.(sources_dir, many, "../current.osm.pbf.partial") do
          {:ok, _out} ->
            File.rm(current)
            File.rename!(current <> ".partial", current)
            :ok

          {:error, code, output} ->
            {:error, :merging, {code, output}}
        end
    end
  end

  defp convert_for_overpass(%{services: services} = state, job_id, osm_dir)
       when is_list(services) do
    if "overpass" in services,
      do: convert_for_overpass(%{state | services: nil}, job_id, osm_dir),
      else: :ok
  end

  defp convert_for_overpass(state, job_id, osm_dir) do
    progress(state, job_id, :converting, %{region: nil, progress: nil})
    bz2 = Path.join(osm_dir, "current.osm.bz2")
    partial = bz2 <> ".partial"

    # Fatal on purpose: a swallowed failure leaves the previous (possibly
    # weeks-old) current.osm.bz2 in place, and overpass re-imports it with no
    # indication the refresh never happened.
    case state.osmium_convert.(osm_dir, "current.osm.pbf", "current.osm.bz2.partial") do
      {:ok, _} ->
        case File.rename(partial, bz2) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error("overpass source conversion reported success but #{partial} is missing")
            {:error, :converting, {:promote, reason}}
        end

      {:error, code, output} ->
        File.rm(partial)

        Logger.error(
          "overpass source conversion failed (#{format_exit(code)}); " <>
            "#{bz2} left untouched and may be stale: #{output}"
        )

        {:error, :converting, {code, output}}
    end
  end

  # An interrupted merge/convert (restart, OOM, kill) strands a multi-hundred-MB
  # `.partial`. Sweep before writing new ones so they neither accumulate nor get
  # mistaken for a completed artifact.
  defp sweep_partials(osm_dir) do
    case File.ls(osm_dir) do
      {:ok, entries} ->
        for name <- entries, String.ends_with?(name, ".partial") do
          path = Path.join(osm_dir, name)
          Logger.info("removing orphaned partial from an interrupted run: #{path}")
          File.rm(path)
        end

        :ok

      {:error, _reason} ->
        :ok
    end
  end

  # Valhalla's image scans its OWN mount (/custom_files) for `*.osm.pbf` and
  # exits with "No local PBF files ... Nothing to do" when it finds none, then
  # restart-loops. The region PBF lives in the osm dir, which is mounted at
  # /osm — somewhere the image never looks — so routing never had tiles to
  # build from. Stage a copy the same way OTP gets one.
  defp stage_valhalla(state, job_id, osm_dir) do
    progress(state, job_id, :staging, %{region: nil, progress: nil})
    valhalla_dir = Path.join(state.data_dir, "valhalla")
    File.mkdir_p!(valhalla_dir)

    current = Path.join(osm_dir, "current.osm.pbf")
    dst = Path.join(valhalla_dir, "region.osm.pbf")
    File.rm(dst)

    case File.cp(current, dst) do
      :ok -> invalidate_valhalla(valhalla_dir)
      {:error, reason} -> {:error, :staging, {:copy, reason}}
    end
  end

  # The pinned image hashes PBF filenames, not their contents. Replacing
  # region.osm.pbf otherwise leaves both its tile cache and old tar in use.
  defp invalidate_valhalla(dir) do
    Enum.reduce_while(
      ~w(file_hashes.txt .file_hashes.txt valhalla_tiles.tar valhalla_tiles admin_data),
      :ok,
      fn name, :ok ->
        case File.rm_rf(Path.join(dir, name)) do
          {:ok, _} -> {:cont, :ok}
          {:error, reason, path} -> {:halt, {:error, :staging, {:invalidate_graph, path, reason}}}
        end
      end
    )
  end

  defp stage_otp(state, job_id, osm_dir, gtfs_dir, entries) do
    progress(state, job_id, :staging, %{
      region: nil,
      progress: nil,
      detail: time_zone_detail(entries)
    })

    otp_dir = Path.join(state.data_dir, "otp")
    File.mkdir_p!(otp_dir)

    current = Path.join(osm_dir, "current.osm.pbf")
    pbf_dst = Path.join(otp_dir, "region.osm.pbf")
    File.rm(pbf_dst)

    case File.cp(current, pbf_dst) do
      :ok ->
        if is_nil(state.transit_sources), do: stage_otp_gtfs(gtfs_dir, otp_dir)
        File.rm(Path.join(otp_dir, "graph.obj"))
        stage_otp_build_config(otp_dir, entries)

      {:error, reason} ->
        {:error, :staging, {:copy, reason}}
    end
  end

  defp stage_transit(state, job_id, osm_dir, gtfs_dir, entries) do
    with :ok <- stage_otp(state, job_id, osm_dir, gtfs_dir, entries),
         do: prepare_transit_sources(state, job_id)
  end

  defp prepare_transit_sources(%{transit_sources: nil}, _job_id), do: :ok

  defp prepare_transit_sources(state, job_id) do
    usable =
      TransitSourceFiles.prepare(state.transit_sources, state.data_dir, fn label ->
        progress(state, job_id, :downloading, %{region: label, progress: nil})
      end)

    TransitSourceFiles.stage(usable, state.data_dir)
  end

  # Whether OTP got a time zone is otherwise invisible: an ambiguous set writes
  # no config and the restriction loss is silent. Say which way it went on the
  # staging row, where the rest of that stage's work is already reported.
  defp time_zone_detail(entries) do
    case OtpBuildConfig.resolve(entries) do
      {:ok, zone} -> "time zone #{zone}"
      :ambiguous -> "no time zone — the selected regions span more than one"
    end
  end

  # OTP resolves OSM opening hours against one time zone for the whole extract,
  # and skips every time-restricted entity when it has none. Pin it when the
  # selected regions agree; when they do not, delete rather than keep, or the
  # zone from a previous single-country apply silently outlives its extract.
  defp stage_otp_build_config(otp_dir, entries) do
    path = Path.join(otp_dir, "build-config.json")

    case OtpBuildConfig.resolve(entries) do
      {:ok, zone} ->
        case File.write(path, OtpBuildConfig.render(zone)) do
          :ok -> :ok
          {:error, reason} -> {:error, :staging, {:build_config, reason}}
        end

      :ambiguous ->
        File.rm(path)
        :ok
    end
  end

  defp stage_otp_gtfs(gtfs_dir, otp_dir) do
    gtfs_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".zip"))
    |> Enum.each(fn name ->
      dst = Path.join(otp_dir, name)
      if not File.exists?(dst), do: File.cp!(Path.join(gtfs_dir, name), dst)
    end)
  end

  # Filter BEFORE announcing. The timeline builds its sidecar rows from this
  # broadcast, so naming a service that is switched off hands it a row that can
  # never start — which the timeline then has to guess about, and guessed wrong
  # for an enabled service that simply had not logged yet.
  # The convert failure is what fails the apply, but a restart that also failed
  # must not vanish with it: unrecorded, the valhalla and otp rows go green off
  # the old container's log ticks.
  defp restart_after_failed_convert(state, job_id) do
    case restart_services(
           state,
           job_id,
           (@ingest_services ++ [Atlas.Settings.transit_backend()]) -- ["overpass"]
         ) do
      :ok -> :ok
      {:error, phase, reason} -> broadcast_error(job_id, phase, reason)
    end
  end

  defp broadcast_error(job_id, phase, reason) do
    broadcast({:apply_error, %{job_id: job_id, phase: phase, reason: format_reason(reason)}})
  end

  defp restart_services(state, job_id, services) do
    progress(state, job_id, :restarting, %{region: nil, progress: nil})

    enabled =
      Enum.filter(services, fn name ->
        state.enabled?.(name) and (is_nil(state.services) or name in state.services)
      end)

    broadcast({:apply_restarting, enabled})

    case state.restart.(enabled) do
      :ok -> :ok
      {:error, reason} -> {:error, :restarting, reason}
    end
  end

  defp default_enabled?(name),
    do: match?(%{enabled?: true}, Atlas.Control.Safe.snapshot(name))

  # DockerCompose documents that callers must not discard failures. Swallowing
  # them reported a successful apply for a restart that never happened, leaving
  # the sidecar rows to settle as "no progress reported".
  #
  # Every service is attempted even when an earlier one fails: they are
  # independent, and stopping early would leave the rest on stale data with
  # nothing said about it.
  defp default_restart(names) do
    names
    |> Enum.map(fn name -> {name, Atlas.Control.DockerCompose.restart(name)} end)
    |> summarize_restarts()
  end

  @doc """
  Fold `{name, DockerCompose.restart/1 result}` pairs into `:ok` or a single
  error naming every service that failed. Public so the reporting is testable
  without a docker daemon.
  """
  def summarize_restarts(results) do
    failures =
      for {name, {:error, code, output}} <- results,
          do: "#{name}: exit #{code}: #{String.trim(to_string(output))}"

    if failures == [], do: :ok, else: {:error, Enum.join(failures, "; ")}
  end

  defp progress(state, job_id, phase, extra) do
    payload = Map.merge(%{job_id: job_id, phase: phase}, extra)
    send(__MODULE__, {:applier_progress, Map.take(payload, [:phase, :region, :progress])})
    broadcast({:apply_progress, payload})
    log_phase_change(state, phase, extra[:region])
  end

  # One line per phase transition (downloading/merging/…) so multi-hour
  # applies leave a trail in `docker logs`.
  defp log_phase_change(_state, phase, region) do
    key = {__MODULE__, :logged_phase}

    if Process.get(key) != phase do
      Process.put(key, phase)
      suffix = if region, do: " (#{region})", else: ""
      Logger.info("region apply phase: #{phase}#{suffix}")
    end
  end

  defp broadcast(msg), do: Phoenix.PubSub.broadcast(Atlas.PubSub, @topic, msg)

  defp format_reason({url, reason}) when is_binary(url), do: "#{url}: #{format_reason(reason)}"
  defp format_reason({:http_status, status}), do: "HTTP #{status}"
  defp format_reason({code, output}) when is_integer(code), do: "exit #{code}: #{output}"
  defp format_reason({:stalled, detail}), do: "stalled: #{detail}"
  defp format_reason(%{__exception__: true} = e), do: Exception.message(e)
  defp format_reason(other), do: inspect(other)

  defp format_exit(code) when is_integer(code), do: "exit #{code}"
  defp format_exit(:stalled), do: "stalled"
  defp format_exit(other), do: inspect(other)
end
