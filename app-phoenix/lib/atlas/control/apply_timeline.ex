defmodule Atlas.Control.ApplyTimeline do
  @moduledoc """
  One timeline for a region apply, from the first byte downloaded to the
  sidecars actually being ready to serve.

  Folds two existing event streams — `RegionApplier`'s lifecycle events and
  `ServiceState`'s per-service snapshots — into a single struct the LiveViews
  render without any merge logic of their own.

  A `Measure` with `total: nil` means the total is genuinely unknown. Callers
  must render observed facts (bytes so far, elapsed) rather than a bar;
  `percentage/1` returns `nil` for such a measure by construction.

  ## The applier is not the finish line

  `{:apply_done, …}` fires the moment `docker compose restart` returns, with
  Valhalla possibly hours from serving a route. It therefore completes only
  the *applier* stages; each sidecar row finishes on its own `ready?`. A
  sidecar row never moves backwards out of `:done`.
  """

  defmodule Measure do
    @moduledoc "A progress reading. `total: nil` means indeterminate."
    defstruct [:kind, :current, :total]

    @type t :: %__MODULE__{
            kind: :bytes | :fraction | :count,
            current: number(),
            total: number() | nil
          }
  end

  defmodule Item do
    @moduledoc "One file within a stage."
    defstruct [:label, :source, :state, :measure]

    @type t :: %__MODULE__{
            label: String.t(),
            source: String.t() | nil,
            state: :pending | :running | :done | :error,
            measure: Measure.t() | nil
          }
  end

  defmodule Stage do
    @moduledoc "One step of the journey."
    defstruct [
      :key,
      :label,
      :detail,
      :measure,
      :started_at,
      :finished_at,
      :error,
      state: :pending,
      items: []
    ]

    @type t :: %__MODULE__{
            key: atom(),
            label: String.t(),
            state: :pending | :running | :done | :skipped | :error,
            items: [Item.t()]
          }
  end

  defmodule Timeline do
    @moduledoc "The whole journey for one apply job."
    defstruct [
      :job_id,
      :started_at,
      :finished_at,
      :applier_finished_at,
      regions: [],
      status: :running,
      current_step: 1,
      stages: []
    ]
  end

  @applier_stages [
    {:download, "Download region data"},
    {:merge, "Merge into current.osm.pbf"},
    {:stage_otp, "Stage transit inputs"},
    {:convert, "Convert for Overpass"}
  ]

  @phase_stage %{
    downloading: :download,
    merging: :merge,
    staging: :stage_otp,
    converting: :convert
  }

  # Sidecars a region apply can restart (mirrors RegionApplier's
  # `@ingest_services`). A compile-time literal map — not
  # `String.to_existing_atom/1` — turns a broadcast's string name into a
  # stage key. `to_existing_atom/1` only succeeds once something has called
  # `String.to_atom/1` on that exact string at runtime, so a `:service_update`
  # for a known service this BEAM has never turned into an atom (fresh boot,
  # e.g. "overpass" broadcasting before any apply job ran) would hit an atom
  # that was never created and raise `ArgumentError`. The atoms below are
  # literals in this module's own source, so they exist the moment the module
  # is loaded. `Map.fetch/2` can then only ever hit or miss, never raise.
  @service_atoms %{
    "valhalla" => :valhalla,
    "overpass" => :overpass,
    "otp" => :otp,
    "motis" => :motis
  }
  @service_keys Map.values(@service_atoms)

  # The same set as names, seeded at `:apply_start` so `step N of M` is fixed
  # for the whole run (the data-model note in the spec says M stays stable).
  # `{:apply_restarting, …}` then says which of them were actually restarted;
  # the rest are marked `:skipped` rather than silently dropped, so "why is
  # my Overpass data stale" has a row to answer it.
  @ingest_services ~w(valhalla overpass)

  # The only two parser phases whose number is measured rather than invented:
  # both come from a literal `(N%)` in the service's own log
  # (`Parsers.Valhalla`'s `@progress_re`, `Parsers.OTP`'s `@street_graph_re`).
  # Every other phase carries a hardcoded marker — Overpass "ingesting" is
  # always 0.6, OTP "loading-osm" always 0.2 — which rendered as a percentage
  # would be exactly the synthetic progress this feature exists to avoid. The
  # parsers stay untouched; other surfaces consume them.
  # Only phases whose number the parser actually measured. `building-tiles` is
  # deliberately absent: Parsers.Valhalla assigns it a flat 0.5 on sight of
  # "Running valhalla_build_tiles", and its one real-progress regex matches
  # "Build street graph progress:" — OpenTripPlanner's wording, which Valhalla
  # never emits. So 0.5 is the only value that phase can ever report, frozen
  # for the whole build. Showing it would be the invented number this whole
  # feature exists to avoid.
  @measured_phases ~w(building-graph)

  # A sidecar the applier chose not to restart. The applier excludes one
  # exactly when the artifact it consumes failed to build (see
  # `RegionApplier.run_pipeline/4`'s `@ingest_services -- ["overpass"]`), but
  # the timeline only observes the exclusion, so it says only that.
  @not_restarted "not restarted by this apply"

  use GenServer

  @topic "control:timeline"

  @doc "Stable PubSub topic carrying `{:timeline, %Timeline{}}`."
  def topic, do: @topic

  @doc "The current timeline, or nil when no apply has run since boot."
  def current, do: GenServer.call(__MODULE__, :current)

  @doc """
  Drop the current timeline.

  A finished apply otherwise stays on screen until the next one starts, so the
  Region tab and `/admin/apply` kept rendering a run that ended days ago.
  """
  def dismiss, do: GenServer.call(__MODULE__, :dismiss)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Atlas.PubSub, Atlas.Control.RegionApplier.topic())

    Enum.each(Map.keys(@service_atoms), fn name ->
      Phoenix.PubSub.subscribe(Atlas.PubSub, "control:service:#{name}")
    end)

    # A crash mid-apply (e.g. RegionApplier restarts us under :rest_for_one)
    # resets state to nil, but subscribers (LiveViews) are still subscribed
    # to this topic — they outlive our pid. Without this broadcast they'd
    # keep rendering a frozen, now-stale `:running` timeline forever.
    {:ok, publish(nil)}
  end

  @impl true
  def handle_call(:current, _from, timeline), do: {:reply, timeline, timeline}

  def handle_call(:dismiss, _from, _timeline), do: {:reply, :ok, publish(nil)}

  @impl true
  def handle_info({:apply_start, %{job_id: job_id, regions: regions}}, _timeline) do
    timeline = %{
      start(regions, @ingest_services ++ [Atlas.Settings.transit_backend()], now())
      | job_id: job_id
    }

    {:noreply, publish(timeline)}
  end

  # Before an apply starts there is nothing to fold into.
  def handle_info(_event, nil), do: {:noreply, nil}

  def handle_info(event, timeline) do
    {:noreply, maybe_publish(timeline, apply_event(timeline, event, now()))}
  end

  # Ingest services broadcast a snapshot on every log-derived progress tick,
  # most of which fold into no change (e.g. a `:service_update` for a
  # service this job never restarted, so it has no matching stage). Only
  # publish when the fold actually produced a different timeline, so
  # subscribers don't get a full `%Timeline{}` push per tick with nothing
  # new to render.
  defp maybe_publish(old, new) when old == new, do: new
  defp maybe_publish(_old, new), do: publish(new)

  defp publish(timeline) do
    Phoenix.PubSub.broadcast(Atlas.PubSub, @topic, {:timeline, timeline})
    timeline
  end

  defp now, do: DateTime.utc_now()

  defp resolve_service_atom(name) do
    case Map.fetch(@service_atoms, name) do
      {:ok, key} -> [key]
      :error -> []
    end
  end

  defp new_service_stage(key),
    do: %Stage{key: key, label: key |> Atom.to_string() |> String.capitalize()}

  @doc """
  Build the initial timeline. `services` are the sidecars in this job's
  journey; each gets a `:pending` row up front so `step N of M` never changes
  M mid-run. A row only starts folding its service's snapshots once
  `{:apply_restarting, …}` names it — the attribution rule in the spec.
  """
  def start(regions, services, now) do
    %Timeline{
      regions: regions,
      started_at: now,
      status: :running,
      current_step: 1,
      stages: Enum.map(@applier_stages, &stage/1) ++ service_stages(services)
    }
  end

  defp service_stages(services) do
    services
    |> Enum.flat_map(&resolve_service_atom/1)
    |> Enum.map(&new_service_stage/1)
  end

  @doc "Percentage for a measure, or nil when the total is unknown."
  def percentage(%Measure{total: total}) when is_nil(total), do: nil
  def percentage(%Measure{total: total}) when total <= 0, do: nil
  # Clamped: a redirected download whose Content-Length undercounts the body
  # leaves current > total, which rendered as "127%".
  def percentage(%Measure{current: current, total: total}),
    do: (current / total * 100) |> round() |> min(100) |> max(0)

  def percentage(nil), do: nil

  @doc "Fold one event into the timeline."
  def apply_event(timeline, {:apply_progress, %{phase: :downloading} = payload}, now) do
    timeline
    |> put_stage(:download, fn stage ->
      stage
      |> mark_running(now)
      |> put_item(payload[:item])
    end)
    |> recompute_step()
  end

  def apply_event(timeline, {:apply_progress, %{phase: phase} = payload}, now)
      when is_map_key(@phase_stage, phase) do
    key = Map.fetch!(@phase_stage, phase)

    timeline
    |> complete_stages_before(key, now)
    |> put_stage(key, &(&1 |> mark_running(now) |> put_detail(payload[:detail])))
    |> recompute_step()
  end

  # `restarting` is the applier handing off to the sidecars: its own work is
  # done, and the service stages take over from here.
  def apply_event(timeline, {:apply_progress, %{phase: :restarting}}, now) do
    timeline
    |> complete_applier_stages(now)
    |> recompute_step()
  end

  # Which sidecars the applier actually restarted. The named ones start
  # folding their ServiceState snapshots from here; the rest are settled as
  # `:skipped` — they are part of this journey and their absence is itself
  # the answer to "why is that service's data stale".
  def apply_event(timeline, {:apply_restarting, services}, now) do
    keys = Enum.flat_map(services, &resolve_service_atom/1)

    timeline
    |> ensure_service_stages(keys)
    |> resolve_restart(MapSet.new(keys), now)
    |> recompute_step()
  end

  # The applier's own work is over; the sidecars' is not. Completing every
  # stage here would stamp `✓` on a Valhalla that is three hours from
  # serving, so only the applier stages finish. The timeline itself settles
  # in `maybe_finish/2`, once no adopted sidecar is still ingesting.
  def apply_event(timeline, {:apply_done, _payload}, now) do
    timeline
    |> complete_applier_stages(now)
    |> Map.put(:applier_finished_at, now)
    |> recompute_step()
    |> maybe_finish(now)
  end

  # A restart that failed did not break the applier's work — every applier stage
  # had already completed when `:restarting` was announced. It broke the
  # sidecars, which never received the new data, so the error belongs on their
  # rows. Blaming `:convert` reported a conversion failure for a conversion that
  # succeeded.
  def apply_event(timeline, {:apply_error, %{phase: :restarting} = payload}, now) do
    message = to_message(payload[:reason])

    stages =
      Enum.map(timeline.stages, fn stage ->
        if sidecar?(stage.key) and stage.state not in [:done, :skipped] do
          %{stage | state: :error, error: message, finished_at: now}
        else
          stage
        end
      end)

    timeline
    |> Map.put(:stages, stages)
    |> Map.put(:status, :error)
    |> Map.put(:finished_at, now)
  end

  def apply_event(timeline, {:apply_error, %{phase: phase} = payload}, now) do
    key = Map.get(@phase_stage, phase, :convert)

    timeline
    |> complete_stages_before(key, now)
    |> put_stage(key, fn stage ->
      %{stage | state: :error, error: to_message(payload[:reason]), finished_at: now}
    end)
    |> skip_pending(now)
    |> Map.put(:status, :error)
    |> Map.put(:finished_at, now)
  end

  def apply_event(timeline, {:service_update, %{name: name} = snapshot}, now) do
    case Map.fetch(@service_atoms, name) do
      {:ok, key} -> fold_service_update(timeline, key, snapshot, now)
      :error -> timeline
    end
  end

  def apply_event(timeline, _event, _now), do: timeline

  defp ensure_service_stages(%Timeline{stages: stages} = timeline, keys) do
    existing = MapSet.new(stages, & &1.key)
    added = keys |> Enum.reject(&MapSet.member?(existing, &1)) |> Enum.map(&new_service_stage/1)

    %{timeline | stages: stages ++ added}
  end

  defp resolve_restart(%Timeline{stages: stages} = timeline, restarted, now) do
    %{timeline | stages: Enum.map(stages, &restart_outcome(&1, restarted, now))}
  end

  defp restart_outcome(%Stage{state: :pending, key: key} = stage, restarted, now) do
    cond do
      not sidecar?(key) -> stage
      MapSet.member?(restarted, key) -> %{stage | state: :running, detail: "restarting"}
      true -> %{stage | state: :skipped, detail: @not_restarted, finished_at: now}
    end
  end

  defp restart_outcome(stage, _restarted, _now), do: stage

  defp fold_service_update(timeline, key, snapshot, now) do
    if adopted?(timeline, key) do
      timeline
      |> put_stage(key, &fold_service(&1, snapshot, now))
      |> recompute_step()
      |> maybe_finish(now)
    else
      timeline
    end
  end

  # The attribution rule: only a service THIS job restarted may fold its
  # snapshots in. A row still `:pending` was seeded but never restarted; a
  # `:skipped` one was explicitly excluded. Letting either absorb a
  # hand-restart's ticks would credit someone else's ingest to this apply.
  # `:skipped` is adoptable again on purpose. It is reached two ways: the
  # service was excluded from `{:apply_restarting, …}` (never ours, and it has
  # no stage at all), or `settle_unstarted/2` guessed from "no tick by
  # :apply_done" that it was disabled. A tick arriving afterwards is proof that
  # guess was wrong — an enabled sidecar that simply had not logged yet — so it
  # must be allowed to correct itself rather than sit at "disabled" while it
  # ingests for hours.
  defp adopted?(timeline, key) do
    Enum.any?(timeline.stages, fn stage ->
      stage.key == key and (stage.state != :pending and re_adoptable?(stage))
    end)
  end

  # `:skipped` is re-adoptable only when it came from `settle_unstarted/2`.
  # A service the applier deliberately excluded keeps its row read-only: a tick
  # from the still-running old container would otherwise turn "not restarted by
  # this apply" into a green tick.
  # `:skipped` means the applier deliberately excluded the service — an
  # observed fact, not a guess. A tick from the still-running old container
  # must not turn "not restarted by this apply" into a green tick.
  defp re_adoptable?(%Stage{state: :skipped}), do: false
  # A row that recorded a failed restart stays failed: the old container keeps
  # logging afterwards, and those ticks describe the process that did NOT get
  # the new data. Only a fresh apply clears it.
  defp re_adoptable?(%Stage{state: :error}), do: false
  defp re_adoptable?(_stage), do: true

  defp fold_service(%Stage{state: :done} = stage, _snapshot, _now), do: stage
  defp fold_service(%Stage{state: :error} = stage, _snapshot, _now), do: stage

  defp fold_service(stage, %{status: :error} = snapshot, now) do
    %{
      stage
      | state: :error,
        error: to_message(snapshot[:last_error]),
        finished_at: stage.finished_at || now
    }
  end

  # `finished_at || now`, never a fresh `now`: a ready service keeps
  # broadcasting (every `GET / HTTP` line changes ServiceState's `last_log`,
  # which `changed?/2` does not filter). Restamping would make each fold
  # produce a different struct, defeat `maybe_publish/2`, and push a full
  # `%Timeline{}` — and the `Repo.all` behind `SettingsPanel.update/2` — to
  # every open LiveView once per routing request, forever.
  defp fold_service(stage, %{ready?: true}, now) do
    %{
      stage
      | state: :done,
        detail: "ready",
        finished_at: stage.finished_at || now,
        measure: nil
    }
  end

  # A finished sidecar stays finished. A later non-ready tick — a hand
  # restart after this apply, a ServiceState reboot re-deriving `ready?`
  # from the DB — belongs to a different story and must not un-finish it.

  defp fold_service(stage, snapshot, now) do
    %{
      stage
      | state: :running,
        started_at: stage.started_at || now,
        detail: snapshot[:phase] || stage.detail,
        measure: service_measure(snapshot[:phase], snapshot[:progress])
    }
  end

  defp service_measure(phase, progress)
       when is_number(progress) and phase in @measured_phases,
       do: %Measure{kind: :fraction, current: progress, total: 1}

  defp service_measure(_phase, _progress), do: nil

  defp sidecar?(key), do: key in @service_keys

  defp stage({key, label}), do: %Stage{key: key, label: label}

  defp put_stage(%Timeline{stages: stages} = timeline, key, fun) do
    %{timeline | stages: Enum.map(stages, fn s -> if s.key == key, do: fun.(s), else: s end)}
  end

  defp mark_running(%Stage{state: :pending} = stage, now),
    do: %{stage | state: :running, started_at: now}

  defp mark_running(stage, _now), do: stage

  defp put_item(stage, nil), do: stage

  defp put_item(%Stage{items: items} = stage, %{label: label} = raw) do
    item = %Item{
      label: label,
      source: raw[:source],
      state: :running,
      measure: %Measure{kind: :bytes, current: raw[:current] || 0, total: raw[:total]}
    }

    %{stage | items: merge_item(items, item)}
  end

  # A new label means the previous file finished: the applier downloads
  # sequentially, so anything still "running" when a new one starts is done.
  defp merge_item(items, %Item{label: label} = item) do
    if Enum.any?(items, &(&1.label == label)) do
      replace_item(items, item)
    else
      Enum.map(items, &finish_item/1) ++ [item]
    end
  end

  defp replace_item(items, %Item{label: label} = item) do
    Enum.map(items, &if(&1.label == label, do: item, else: &1))
  end

  defp finish_item(%Item{state: :running} = item), do: %{item | state: :done}
  defp finish_item(item), do: item

  defp recompute_step(%Timeline{stages: stages} = timeline) do
    index = Enum.find_index(stages, &(&1.state in [:running, :pending])) || length(stages) - 1
    %{timeline | current_step: index + 1}
  end

  defp applier_keys, do: Enum.map(@applier_stages, fn {key, _label} -> key end)

  defp complete_stages_before(timeline, key, now) do
    keys = applier_keys()
    cutoff = Enum.find_index(keys, &(&1 == key)) || 0
    earlier = Enum.take(keys, cutoff)

    Enum.reduce(earlier, timeline, fn k, acc ->
      put_stage(acc, k, &finish_stage(&1, now))
    end)
  end

  defp complete_applier_stages(timeline, now) do
    Enum.reduce(applier_keys(), timeline, fn k, acc ->
      put_stage(acc, k, &finish_stage(&1, now))
    end)
  end

  defp finish_stage(%Stage{state: state} = stage, _now) when state in [:error, :skipped],
    do: stage

  defp finish_stage(%Stage{finished_at: nil} = stage, now),
    do: %{stage | state: :done, finished_at: now, items: Enum.map(stage.items, &finish_item/1)}

  defp finish_stage(stage, _now), do: %{stage | state: :done}

  # Only stages that never started. A sidecar already adopted by
  # `{:apply_restarting, …}` is genuinely ingesting right now — the applier
  # restarts Valhalla and OTP even when the Overpass conversion failed — and
  # must keep running rather than be declared skipped.
  defp skip_pending(%Timeline{stages: stages} = timeline, now) do
    %{timeline | stages: Enum.map(stages, &skip_if_pending(&1, now))}
  end

  defp skip_if_pending(%Stage{state: :pending, key: key} = stage, now) do
    detail = if sidecar?(key), do: @not_restarted, else: stage.detail
    %{stage | state: :skipped, detail: detail, finished_at: now}
  end

  defp skip_if_pending(stage, _now), do: stage

  # The journey ends when the data is usable, not when the applier returned:
  # the timeline stays `:running` while an adopted sidecar is still ingesting.
  #
  # "Still ingesting" requires the sidecar to have actually reported —
  # `started_at` is stamped by its first ServiceState tick, not by adoption.
  # The applier names every ingest service in `{:apply_restarting, …}` and
  # only filters by `enabled?` afterwards, and services ship disabled, so a
  # row that never ticks is a service that is not running. Waiting on those
  # would leave the default install `:running` forever. `:done` is terminal,
  # so a late first tick can never drag the timeline backwards either.
  defp maybe_finish(%Timeline{status: status} = timeline, _now) when status != :running,
    do: timeline

  defp maybe_finish(%Timeline{applier_finished_at: nil} = timeline, _now), do: timeline

  defp maybe_finish(timeline, now) do
    if Enum.any?(timeline.stages, &still_ingesting?/1) do
      timeline
    else
      timeline
      |> Map.merge(%{status: :done, finished_at: now})
      |> recompute_step()
    end
  end

  # A row is ingesting from the moment it is announced, tick or no tick. The
  # applier filters on `enabled?` BEFORE announcing, so every named service was
  # actually restarted and will report — one that has not logged in the seconds
  # before `:apply_done` is starting, not absent.
  defp still_ingesting?(%Stage{key: key, state: :running}), do: sidecar?(key)
  defp still_ingesting?(_stage), do: false

  # A stage can report a decision it made — which time zone OTP was pinned to,
  # or that the regions disagreed and none was. Absent detail leaves whatever
  # the stage already said, so a later progress tick cannot erase it.
  defp put_detail(stage, nil), do: stage
  defp put_detail(stage, detail), do: %{stage | detail: detail}

  defp to_message(reason) when is_binary(reason), do: reason
  defp to_message(reason), do: inspect(reason)
end
