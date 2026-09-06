defmodule Atlas.Control.ApplyTimelineTest do
  use Atlas.DataCase, async: false

  alias Atlas.Control.ApplyTimeline
  alias Atlas.Control.ApplyTimeline.Timeline

  @now ~U[2026-08-11 20:00:00Z]

  @later ~U[2026-08-11 21:30:00Z]

  defp start_timeline(services \\ []) do
    ApplyTimeline.start(["Germany"], services, @now)
  end

  defp stage(%Timeline{stages: stages}, key), do: Enum.find(stages, &(&1.key == key))

  defp event(timeline, event, now \\ @now),
    do: ApplyTimeline.apply_event(timeline, event, now)

  defp restarting(timeline, services, now \\ @now),
    do: event(timeline, {:apply_restarting, services}, now)

  test "a fresh timeline lists the applier stages as pending" do
    timeline = start_timeline()

    assert timeline.status == :running
    assert timeline.regions == ["Germany"]
    assert timeline.current_step == 1
    assert Enum.map(timeline.stages, & &1.key) == [:download, :merge, :stage_otp, :convert]
    assert Enum.all?(timeline.stages, &(&1.state == :pending))
  end

  test "a download event opens a per-file row carrying label, source and bytes" do
    timeline =
      start_timeline()
      |> ApplyTimeline.apply_event(
        {:apply_progress,
         %{
           phase: :downloading,
           region: "germany",
           item: %{
             label: "germany-latest.osm.pbf",
             source: "https://download.geofabrik.de/europe/germany-latest.osm.pbf",
             current: 1024,
             total: 4096
           }
         }},
        @now
      )

    download = stage(timeline, :download)

    assert download.state == :running
    assert [item] = download.items
    assert item.label == "germany-latest.osm.pbf"
    assert item.source == "https://download.geofabrik.de/europe/germany-latest.osm.pbf"
    assert item.measure.kind == :bytes
    assert item.measure.current == 1024
    assert item.measure.total == 4096
  end

  test "a second file becomes a second row, and the first is marked done" do
    timeline =
      start_timeline()
      |> ApplyTimeline.apply_event(
        {:apply_progress,
         %{
           phase: :downloading,
           region: "germany",
           item: %{label: "a.pbf", source: "http://x/a.pbf", current: 10, total: 10}
         }},
        @now
      )
      |> ApplyTimeline.apply_event(
        {:apply_progress,
         %{
           phase: :downloading,
           region: "austria",
           item: %{label: "b.pbf", source: "http://x/b.pbf", current: 5, total: 20}
         }},
        @now
      )

    assert [a, b] = stage(timeline, :download).items
    assert a.label == "a.pbf"
    assert a.state == :done
    assert b.label == "b.pbf"
    assert b.state == :running
  end

  test "an unknown total yields an indeterminate measure, never a fraction" do
    timeline =
      start_timeline()
      |> ApplyTimeline.apply_event(
        {:apply_progress,
         %{
           phase: :downloading,
           region: "germany",
           item: %{label: "a.pbf", source: "http://x/a.pbf", current: 999, total: nil}
         }},
        @now
      )

    assert [item] = stage(timeline, :download).items
    assert item.measure.total == nil
    refute ApplyTimeline.percentage(item.measure)
  end

  test "advancing to a later phase completes the earlier stages" do
    timeline =
      start_timeline()
      |> ApplyTimeline.apply_event(
        {:apply_progress, %{phase: :downloading, region: "germany"}},
        @now
      )
      |> ApplyTimeline.apply_event({:apply_progress, %{phase: :converting, region: nil}}, @now)

    assert stage(timeline, :download).state == :done
    assert stage(timeline, :merge).state == :done
    assert stage(timeline, :stage_otp).state == :done
    assert stage(timeline, :convert).state == :running
    assert timeline.current_step == 4
  end

  test "apply_done completes every remaining applier stage" do
    timeline =
      start_timeline()
      |> ApplyTimeline.apply_event(
        {:apply_progress, %{phase: :downloading, region: "germany"}},
        @now
      )
      |> ApplyTimeline.apply_event({:apply_done, %{}}, @now)

    assert timeline.status == :done
    assert timeline.finished_at == @now
    assert Enum.all?(timeline.stages, &(&1.state == :done))
  end

  test "apply_error marks the failing stage and skips the rest" do
    timeline =
      start_timeline()
      |> ApplyTimeline.apply_event({:apply_progress, %{phase: :converting, region: nil}}, @now)
      |> ApplyTimeline.apply_event(
        {:apply_error, %{phase: :converting, reason: "no space left on device"}},
        @now
      )

    assert timeline.status == :error
    assert stage(timeline, :convert).state == :error
    assert stage(timeline, :convert).error == "no space left on device"
    assert stage(timeline, :download).state == :done
  end

  test "apply_error on an early phase skips the untouched later stages" do
    timeline =
      start_timeline()
      |> ApplyTimeline.apply_event(
        {:apply_progress, %{phase: :downloading, region: "germany"}},
        @now
      )
      |> ApplyTimeline.apply_event(
        {:apply_error, %{phase: :downloading, reason: "network unreachable"}},
        @now
      )

    assert timeline.status == :error
    assert stage(timeline, :download).state == :error
    assert stage(timeline, :download).error == "network unreachable"
    assert stage(timeline, :merge).state == :skipped
    assert stage(timeline, :stage_otp).state == :skipped
    assert stage(timeline, :convert).state == :skipped
  end

  defp snapshot(name, fields) do
    Map.merge(
      %{name: name, status: :running, phase: nil, progress: nil, ready?: false, last_error: nil},
      fields
    )
  end

  test "an adopted service reports its ingest phase and real percentage" do
    timeline =
      start_timeline(["valhalla"])
      |> event({:apply_progress, %{phase: :restarting}})
      |> restarting(["valhalla"])
      |> event({:service_update, tiles_snapshot()})

    valhalla = stage(timeline, :valhalla)

    assert valhalla.state == :running
    assert valhalla.detail == "building-tiles"
    # No percentage: Parsers.Valhalla fabricates building-tiles progress, so
    # the phase text is all the timeline can honestly report for it.
    refute ApplyTimeline.percentage(valhalla.measure)
  end

  test "a service reporting ready completes its stage" do
    timeline =
      start_timeline(["overpass"])
      |> event({:apply_progress, %{phase: :restarting}})
      |> restarting(["overpass"])
      |> event({:service_update, snapshot("overpass", %{phase: "ready", ready?: true})})

    assert stage(timeline, :overpass).state == :done
  end

  test "a service this job never restarted is not adopted" do
    timeline =
      start_timeline(["valhalla"])
      |> event({:service_update, snapshot("overpass", %{phase: "ingesting"})})

    assert stage(timeline, :overpass) == nil

    assert Enum.map(timeline.stages, & &1.key) ==
             [:download, :merge, :stage_otp, :convert, :valhalla]
  end

  test "a seeded but not-yet-restarted row ignores that service's snapshots" do
    # The row exists from apply_start so `step N of M` is stable, but until
    # {:apply_restarting, …} names it the service is nobody's business: a
    # hand restart mid-apply must not be credited to this job.
    timeline = start_timeline(["valhalla"])

    result =
      event(timeline, {:service_update, snapshot("valhalla", %{phase: "parsing", progress: 0.1})})

    assert result == timeline
    assert stage(result, :valhalla).state == :pending
  end

  test "a failing service errors its stage" do
    timeline =
      start_timeline(["otp"])
      |> event({:apply_progress, %{phase: :restarting}})
      |> restarting(["otp"])
      |> event({:service_update, snapshot("otp", %{status: :error, last_error: "OOM"})})

    assert stage(timeline, :otp).state == :error
    assert stage(timeline, :otp).error == "OOM"
  end

  @all_sidecars ["valhalla", "overpass", "otp"]

  defp tiles_snapshot, do: snapshot("valhalla", %{phase: "building-tiles", progress: 0.34})
  defp parsing_snapshot, do: snapshot("valhalla", %{phase: "parsing", progress: 0.1})
  defp valhalla_topic, do: "control:service:valhalla"

  defp ingesting_timeline do
    start_timeline(@all_sidecars)
    |> event({:apply_progress, %{phase: :restarting}})
    |> restarting(@all_sidecars)
    |> event({:service_update, snapshot("valhalla", %{phase: "building-tiles", progress: 0.34})})
  end

  defp convert_failed_timeline do
    start_timeline(@all_sidecars)
    |> event({:apply_progress, %{phase: :converting, region: nil}})
    |> event({:apply_progress, %{phase: :restarting}})
    |> restarting(["valhalla", "otp"])
    |> event({:service_update, snapshot("valhalla", %{phase: "building-tiles", progress: 0.34})})
    |> event({:service_update, snapshot("otp", %{phase: "building-graph", progress: 0.12})})
    |> event({:apply_error, %{phase: :converting, reason: "no space left on device"}}, @later)
  end

  # Stage keys are looked up from a literal map rather than derived from the
  # name at runtime: nothing in this file should depend on the atom table.
  @stage_keys %{"valhalla" => :valhalla, "overpass" => :overpass, "otp" => :otp}

  defp service_measure_for(name, fields) do
    start_timeline([name])
    |> restarting([name])
    |> event({:service_update, snapshot(name, fields)})
    |> stage(Map.fetch!(@stage_keys, name))
  end

  describe "apply_done next to a live sidecar" do
    test "apply_done leaves an ingesting sidecar running, never done" do
      timeline = event(ingesting_timeline(), {:apply_done, %{}}, @later)

      valhalla = stage(timeline, :valhalla)

      assert valhalla.state == :running,
             "docker compose restart returning is not Valhalla finishing"

      assert valhalla.finished_at == nil
      assert valhalla.detail == "building-tiles"

      applier = [:download, :merge, :stage_otp, :convert]
      assert Enum.all?(applier, &(stage(timeline, &1).state == :done))
    end

    test "the timeline stays running while a sidecar is still ingesting" do
      timeline = event(ingesting_timeline(), {:apply_done, %{}}, @later)

      assert timeline.status == :running
      assert timeline.finished_at == nil
      assert timeline.applier_finished_at == @later
    end

    test "the timeline finishes once the last ingesting sidecar reports ready" do
      # Every announced sidecar has to report: the journey ends when the data
      # is usable, and all three ingest services serve it.
      timeline =
        Enum.reduce(
          @all_sidecars,
          event(ingesting_timeline(), {:apply_done, %{}}, @later),
          fn name, acc ->
            event(acc, {:service_update, snapshot(name, %{phase: "ready", ready?: true})}, @later)
          end
        )

      assert timeline.status == :done
      assert timeline.finished_at == @later
      assert stage(timeline, :valhalla).state == :done
    end

    test "a sidecar row never moves back out of done" do
      timeline =
        ingesting_timeline()
        |> event({:service_update, snapshot("valhalla", %{phase: "ready", ready?: true})})
        |> event({:service_update, parsing_snapshot()}, @later)

      assert stage(timeline, :valhalla).state == :done
    end

    test "a sidecar the applier excluded does not hold the timeline open" do
      # Only announced services pin the timeline. One the applier left out —
      # Overpass, when its source failed to convert — is settled :skipped at
      # announcement time and must not keep the journey running forever.
      timeline =
        start_timeline(@all_sidecars)
        |> restarting(["valhalla"])
        |> event({:apply_done, %{}}, @later)
        |> event({:service_update, snapshot("valhalla", %{phase: "ready", ready?: true})}, @later)

      assert timeline.status == :done
      assert stage(timeline, :overpass).state == :skipped
    end
  end

  describe "sidecar percentages" do
    test "a measured phase keeps its percentage" do
      # building-graph is the only sidecar phase whose number the parser really
      # captures (OTP's log carries an explicit "(N%)"). building-tiles used to
      # be asserted here too, but Parsers.Valhalla fabricates that one — see
      # "an invented phase marker never becomes a percentage" below.
      otp = service_measure_for("otp", %{phase: "building-graph", progress: 0.55})

      assert ApplyTimeline.percentage(otp.measure) == 55
    end

    test "an invented phase marker never becomes a percentage" do
      # These numbers are hardcoded in the parsers as phase markers, not
      # measured: Parsers.Overpass writes 0.6 for every "ingesting" line and
      # 0.2 for every "downloading" one; Parsers.OTP writes 0.7/0.9/0.5/0.2.
      # Rendering them would print "Overpass ingesting 60%".
      for {name, phase, progress} <- [
            {"overpass", "ingesting", 0.6},
            {"overpass", "downloading", 0.2},
            {"otp", "trip-patterns", 0.7},
            {"otp", "saving-graph", 0.9},
            {"otp", "loading-osm", 0.2},
            {"valhalla", "building-elevation", 0.4},
            {"valhalla", "building-admins", 0.3},
            {"valhalla", "parsing", 0.1}
          ] do
        found = service_measure_for(name, %{phase: phase, progress: progress})

        assert found.measure == nil,
               "#{name} #{phase} carries an invented #{progress}, which must not render"

        assert found.detail == phase, "the phase text is what the row falls back to"
      end
    end
  end

  test "a repeated ready snapshot folds into no change at all" do
    # ServiceState broadcasts on every log line a ready service emits (each
    # one changes `last_log`, which `changed?/2` does not filter). If the
    # fold restamps anything, `maybe_publish/2` pushes a whole %Timeline{}
    # — and the Repo.all behind SettingsPanel.update/2 — per routing request.
    ready = {:service_update, snapshot("valhalla", %{phase: "ready", ready?: true})}

    settled =
      start_timeline(["valhalla"])
      |> restarting(["valhalla"])
      |> event({:service_update, snapshot("valhalla", %{phase: "building-tiles", progress: 0.9})})
      |> event(ready)
      |> event({:apply_done, %{}})

    assert settled.status == :done
    assert event(settled, ready, @later) == settled
  end

  describe "a restart that leaves a service behind" do
    test "the excluded service gets a skipped row with a reason, not no row" do
      overpass = stage(convert_failed_timeline(), :overpass)

      assert overpass, "Overpass must have a row even though it was not restarted"
      assert overpass.state == :skipped
      assert overpass.detail =~ "not restarted"
    end

    test "apply_error leaves the services that ARE running alone" do
      timeline = convert_failed_timeline()

      assert stage(timeline, :valhalla).state == :running
      assert stage(timeline, :otp).state == :running
      assert stage(timeline, :convert).state == :error
      assert timeline.status == :error
    end
  end

  test "a service name outside the known ingest set is ignored entirely" do
    # "photon" is a real Atlas service (see Atlas.Control.Parsers.Photon) but
    # is not one of the three services a region apply can restart, so it is
    # not a key in `ApplyTimeline`'s service map. Deliberately never written
    # as the atom `:photon` anywhere else in this file — unlike "valhalla" /
    # "overpass" / "otp", which this file's own other tests already turn
    # into atoms via `stage(timeline, :valhalla)` and friends, making them
    # exist in the atom table before any test body runs. That pre-existence
    # is exactly what let a prior implementation's `String.to_existing_atom/1`
    # pass every test here while still being able to raise `ArgumentError` in
    # production on a genuine fresh-boot first sighting of a known service
    # name. This test's name carries no such pre-existing atom, so it
    # actually exercises the "unrecognized name" branch as plain string
    # comparison — proving the miss path never touches the atom table at
    # all, regardless of what has or hasn't run before it.
    timeline = start_timeline()

    result =
      ApplyTimeline.apply_event(
        timeline,
        {:service_update, snapshot("photon", %{phase: "extracting", progress: 0.5})},
        @now
      )

    assert result == timeline
  end

  test "apply_restarting adds only recognized services and never raises on an unknown name" do
    result = restarting(start_timeline(), ["overpass", "not-a-real-service"])

    assert Enum.map(result.stages, & &1.key) ==
             [:download, :merge, :stage_otp, :convert, :overpass]
  end

  test "apply_restarting does not duplicate a service the job already listed" do
    result = restarting(start_timeline(["valhalla"]), ["valhalla"])

    assert Enum.map(result.stages, & &1.key) ==
             [:download, :merge, :stage_otp, :convert, :valhalla]
  end

  describe "server" do
    test "init/1 broadcasts {:timeline, nil} so subscribers drop a stale timeline" do
      # This is the whole of the crash handling: under :rest_for_one a
      # RegionApplier crash restarts us with state nil, but the LiveViews
      # subscribed to our topic outlive our pid. Without this broadcast they
      # keep rendering a frozen :running timeline forever. Subscribe first —
      # the broadcast happens inside init/1.
      Phoenix.PubSub.subscribe(Atlas.PubSub, ApplyTimeline.topic())

      start_supervised!(Atlas.Control.ApplyTimeline)

      assert_receive {:timeline, nil}, 1_000
    end

    test "the step count is fixed at apply_start and does not grow mid-run" do
      start_supervised!(Atlas.Control.ApplyTimeline)
      Phoenix.PubSub.subscribe(Atlas.PubSub, ApplyTimeline.topic())

      Phoenix.PubSub.broadcast(
        Atlas.PubSub,
        "control:apply",
        {:apply_start, %{job_id: "j5", regions: ["Germany"]}}
      )

      assert_receive {:timeline, %Timeline{job_id: "j5", stages: stages}}, 1_000

      assert Enum.map(stages, & &1.key) ==
               [:download, :merge, :stage_otp, :convert, :valhalla, :overpass, :motis]

      Phoenix.PubSub.broadcast(
        Atlas.PubSub,
        "control:apply",
        {:apply_restarting, ["valhalla", "motis"]}
      )

      assert_receive {:timeline, %Timeline{stages: after_restart}}, 1_000

      assert length(after_restart) == length(stages),
             "M in `step N of M` must not change mid-run"
    end

    test "a ready service's repeated log ticks do not rebroadcast the timeline" do
      start_supervised!(Atlas.Control.ApplyTimeline)
      Phoenix.PubSub.subscribe(Atlas.PubSub, ApplyTimeline.topic())

      Phoenix.PubSub.broadcast(
        Atlas.PubSub,
        "control:apply",
        {:apply_start, %{job_id: "j6", regions: ["Germany"]}}
      )

      assert_receive {:timeline, %Timeline{job_id: "j6"}}, 1_000

      Phoenix.PubSub.broadcast(Atlas.PubSub, "control:apply", {:apply_restarting, ["valhalla"]})
      assert_receive {:timeline, %Timeline{}}, 1_000

      ready = %{
        name: "valhalla",
        status: :running,
        phase: "ready",
        progress: 1.0,
        ready?: true,
        last_error: nil
      }

      Phoenix.PubSub.broadcast(Atlas.PubSub, "control:service:valhalla", {:service_update, ready})
      assert_receive {:timeline, %Timeline{}}, 1_000

      # Valhalla now serves; every `GET / HTTP` line makes ServiceState
      # broadcast again. None of those may reach the LiveViews.
      for _ <- 1..3 do
        Phoenix.PubSub.broadcast(Atlas.PubSub, valhalla_topic(), {:service_update, ready})
      end

      refute_receive {:timeline, _}, 200
    end

    test "broadcasts a timeline and answers current/0" do
      start_supervised!(Atlas.Control.ApplyTimeline)
      Phoenix.PubSub.subscribe(Atlas.PubSub, ApplyTimeline.topic())

      Phoenix.PubSub.broadcast(
        Atlas.PubSub,
        "control:apply",
        {:apply_start, %{job_id: "j1", regions: ["Germany"]}}
      )

      assert_receive {:timeline, %Timeline{regions: ["Germany"], status: :running}}, 1_000
      assert %Timeline{job_id: "j1"} = ApplyTimeline.current()
    end

    test "adopts a restarted service via {:apply_restarting, services} and skips an unknown name" do
      start_supervised!(Atlas.Control.ApplyTimeline)
      Phoenix.PubSub.subscribe(Atlas.PubSub, ApplyTimeline.topic())

      Phoenix.PubSub.broadcast(
        Atlas.PubSub,
        "control:apply",
        {:apply_start, %{job_id: "j2", regions: ["Germany"]}}
      )

      assert_receive {:timeline, %Timeline{job_id: "j2"}}, 1_000

      Phoenix.PubSub.broadcast(
        Atlas.PubSub,
        "control:apply",
        {:apply_restarting, ["valhalla", "not-a-real-service"]}
      )

      assert_receive {:timeline, %Timeline{} = timeline}, 1_000

      assert Enum.map(timeline.stages, & &1.key) ==
               [:download, :merge, :stage_otp, :convert, :valhalla, :overpass, :motis]

      assert stage(timeline, :valhalla).state == :running
      assert stage(timeline, :overpass).state == :skipped
      assert stage(timeline, :motis).state == :skipped

      assert %Timeline{} = current = ApplyTimeline.current()
      assert stage(current, :valhalla).state == :running
    end

    test "does not rebroadcast when a service update folds into no change" do
      start_supervised!(Atlas.Control.ApplyTimeline)
      Phoenix.PubSub.subscribe(Atlas.PubSub, ApplyTimeline.topic())

      Phoenix.PubSub.broadcast(
        Atlas.PubSub,
        "control:apply",
        {:apply_start, %{job_id: "j3", regions: ["Germany"]}}
      )

      assert_receive {:timeline, %Timeline{job_id: "j3"}}, 1_000

      # "valhalla" was never adopted by this job (apply_start carries no
      # services), so the fold is a no-op: this must not trigger a second
      # broadcast.
      Phoenix.PubSub.broadcast(
        Atlas.PubSub,
        "control:service:valhalla",
        {:service_update,
         %{
           name: "valhalla",
           status: :running,
           phase: "building-tiles",
           progress: 0.1,
           ready?: false,
           last_error: nil
         }}
      )

      refute_receive {:timeline, _}, 200
    end

    test "ignores service updates when no apply is running" do
      start_supervised!(Atlas.Control.ApplyTimeline)

      Phoenix.PubSub.broadcast(
        Atlas.PubSub,
        "control:service:valhalla",
        {:service_update,
         %{
           name: "valhalla",
           status: :running,
           phase: "building-tiles",
           progress: 0.5,
           ready?: false,
           last_error: nil
         }}
      )

      Process.sleep(50)
      refute ApplyTimeline.current()
    end
  end

  describe "no fabricated sidecar percentages" do
    test "building-tiles carries no measure — its number is a parser placeholder" do
      # Parsers.Valhalla assigns 0.5 the moment it sees "Running
      # valhalla_build_tiles", a line with no percentage in it. Its only
      # real-progress regex matches "Build street graph progress:", which is
      # OpenTripPlanner's wording and Valhalla never emits — so 0.5 is the ONLY
      # value this phase can report, frozen for the whole multi-hour build.
      timeline =
        start_timeline(["valhalla"])
        |> event({:apply_progress, %{phase: :restarting}})
        |> restarting(["valhalla"])
        |> event(
          {:service_update, snapshot("valhalla", %{phase: "building-tiles", progress: 0.5})}
        )

      valhalla = stage(timeline, :valhalla)

      assert valhalla.state == :running
      assert valhalla.detail == "building-tiles"
      refute ApplyTimeline.percentage(valhalla.measure)
    end

    test "building-graph still reports its measured percentage" do
      timeline =
        start_timeline(["otp"])
        |> event({:apply_progress, %{phase: :restarting}})
        |> restarting(["otp"])
        |> event({:service_update, snapshot("otp", %{phase: "building-graph", progress: 0.55})})

      assert ApplyTimeline.percentage(stage(timeline, :otp).measure) == 55
    end
  end

  describe "sidecars that never start" do
    test "the timeline does not claim done while an announced sidecar is silent" do
      # A service the applier did not restart gets a row that says so, rather
      # than spinning at "restarting" for the life of the page.
      timeline =
        start_timeline(["valhalla", "overpass"])
        |> event({:apply_progress, %{phase: :restarting}})
        |> restarting(["valhalla"])
        |> event({:service_update, snapshot("valhalla", %{phase: "ready", ready?: true})})
        |> event({:apply_done, %{}})

      assert stage(timeline, :valhalla).state == :done
      overpass = stage(timeline, :overpass)

      assert overpass.state == :skipped
      assert overpass.detail =~ "not restarted"
      refute timeline.current_step > length(timeline.stages)
    end
  end

  describe "terminal-state integrity" do
    test "a finished sidecar is not reddened by a later crash" do
      # The moduledoc's invariant: a sidecar row never moves backwards out of
      # :done. A restart or a ServiceState reboot after this apply belongs to a
      # different story.
      timeline =
        start_timeline(["valhalla"])
        |> restarting(["valhalla"])
        |> event({:service_update, snapshot("valhalla", %{phase: "ready", ready?: true})})

      assert stage(timeline, :valhalla).state == :done

      later =
        event(
          timeline,
          {:service_update, snapshot("valhalla", %{status: :error, phase: "error"})}
        )

      assert stage(later, :valhalla).state == :done
    end

    test "a failed restart does not blame the conversion that succeeded" do
      # :restarting has no entry in @phase_stage, so the error defaulted onto
      # :convert — telling the user their Overpass source failed to build when
      # it built fine and the restart is what broke.
      timeline =
        start_timeline(["valhalla"])
        |> event({:apply_error, %{phase: :restarting, reason: "docker daemon gone"}})

      refute stage(timeline, :convert).state == :error
    end
  end

  describe "percentage/1" do
    test "cannot exceed 100 when the source over-reports" do
      # A redirected download whose Content-Length undercounts the body leaves
      # current > total, which rendered as "127%".
      m = %ApplyTimeline.Measure{kind: :bytes, current: 1270, total: 1000}

      assert ApplyTimeline.percentage(m) == 100
    end

    test "cannot go below zero" do
      m = %ApplyTimeline.Measure{kind: :bytes, current: -5, total: 1000}

      assert ApplyTimeline.percentage(m) == 0
    end
  end

  describe "a stage can say what it decided" do
    test "the staging row reports the time zone it pinned" do
      # Whether OTP got a zone or the config was deleted as ambiguous is
      # otherwise invisible — a silent branch in a feature about silent
      # failures.
      timeline =
        start_timeline(["valhalla"])
        |> event({:apply_progress, %{phase: :staging, detail: "time zone Europe/Berlin"}})

      assert stage(timeline, :stage_otp).detail == "time zone Europe/Berlin"
    end

    test "a progress event without a detail leaves the stage's own text alone" do
      timeline =
        start_timeline(["valhalla"])
        |> event({:apply_progress, %{phase: :staging, detail: "time zone Europe/Berlin"}})
        |> event({:apply_progress, %{phase: :staging}})

      assert stage(timeline, :stage_otp).detail == "time zone Europe/Berlin"
    end
  end

  describe "skip reasons are not interchangeable" do
    test "a service the applier excluded is not adopted by a stray tick" do
      # Overpass is excluded when its source failed to convert. A tick from the
      # still-running old container must not turn that row green.
      timeline =
        start_timeline(["valhalla", "overpass"])
        |> restarting(["valhalla"])

      excluded = stage(timeline, :overpass)
      assert excluded.state == :skipped

      after_tick =
        event(timeline, {:service_update, snapshot("overpass", %{phase: "ready", ready?: true})})

      assert stage(after_tick, :overpass).state == :skipped
    end
  end

  describe "a failed restart" do
    test "does not blame an applier stage that finished" do
      # The real order: :restarting progress completes every applier stage, THEN
      # the error arrives. Without that first event the test proves nothing.
      timeline =
        start_timeline(["valhalla"])
        |> restarting(["valhalla"])
        |> event({:apply_progress, %{phase: :restarting}})
        |> event({:apply_error, %{phase: :restarting, reason: "docker daemon gone"}})

      refute stage(timeline, :convert).state == :error
      assert stage(timeline, :convert).state == :done
    end

    test "reports itself on the sidecars that never got restarted" do
      timeline =
        start_timeline(["valhalla"])
        |> restarting(["valhalla"])
        |> event({:apply_progress, %{phase: :restarting}})
        |> event({:apply_error, %{phase: :restarting, reason: "docker daemon gone"}})

      assert stage(timeline, :valhalla).state == :error
      assert stage(timeline, :valhalla).error =~ "docker daemon gone"
    end
  end

  describe "a restart failure sticks" do
    test "a later log tick does not clear the sidecar's error" do
      # The old container keeps logging after a failed restart; those ticks must
      # not turn the row that recorded the failure back to running/done.
      timeline =
        start_timeline(["valhalla"])
        |> restarting(["valhalla"])
        |> event({:apply_progress, %{phase: :restarting}})
        |> event({:apply_error, %{phase: :restarting, reason: "docker daemon gone"}})

      assert stage(timeline, :valhalla).state == :error

      later =
        event(timeline, {:service_update, snapshot("valhalla", %{phase: "ready", ready?: true})})

      assert stage(later, :valhalla).state == :error
    end
  end

  describe "an announced sidecar that has not logged yet" do
    test "keeps the timeline running rather than settling it done" do
      # The applier now filters on enabled? BEFORE announcing, so every named
      # row is a service that was actually restarted and will tick. A Valhalla
      # that has not logged in the seconds before :apply_done is still starting,
      # not absent — calling the journey finished there is the exact lie this
      # timeline exists to remove.
      timeline =
        start_timeline(["valhalla"])
        |> restarting(["valhalla"])
        |> event({:apply_progress, %{phase: :restarting}})
        |> event({:apply_done, %{}})

      assert timeline.status == :running
      assert stage(timeline, :valhalla).state == :running
    end

    test "finishes once that sidecar reports ready" do
      timeline =
        start_timeline(["valhalla"])
        |> restarting(["valhalla"])
        |> event({:apply_progress, %{phase: :restarting}})
        |> event({:apply_done, %{}})
        |> event({:service_update, snapshot("valhalla", %{phase: "ready", ready?: true})})

      assert timeline.status == :done
      assert stage(timeline, :valhalla).state == :done
    end
  end

  describe "dismiss/0" do
    test "clears a finished timeline so the card stops occupying the panel" do
      # Nothing cleared the last timeline until the next apply started, so a
      # completed run stayed on the Region tab and /admin/apply forever.
      start_supervised!(Atlas.Control.ApplyTimeline)
      Phoenix.PubSub.subscribe(Atlas.PubSub, ApplyTimeline.topic())

      send(ApplyTimeline, {:apply_start, %{job_id: "j1", regions: ["berlin"]}})
      assert_receive {:timeline, %{job_id: "j1"}}

      assert :ok = ApplyTimeline.dismiss()

      assert_receive {:timeline, nil}
      assert ApplyTimeline.current() == nil
    end
  end
end
