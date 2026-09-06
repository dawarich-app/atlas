defmodule Atlas.Control.RegionApplierTest do
  use Atlas.DataCase, async: false

  alias Atlas.Control.{RegionApplier, RegionCatalog}

  @topic "control:apply"

  defp catalog do
    %{
      "berlin" => %RegionCatalog{
        name: "berlin",
        label: "Berlin",
        country_code: "de",
        pbf_urls: ["http://example.test/berlin-latest.osm.pbf"],
        gtfs_url: "http://example.test/vbb.zip",
        gtfs_name: "vbb.gtfs.zip"
      },
      "bayern" => %RegionCatalog{
        name: "bayern",
        label: "Bayern",
        country_code: "de",
        pbf_urls: ["http://example.test/bayern-latest.osm.pbf"]
      },
      "kent" => %RegionCatalog{
        name: "kent",
        label: "Kent",
        country_code: "gb",
        pbf_urls: ["http://example.test/kent-latest.osm.pbf"]
      },
      "europe" => %RegionCatalog{
        name: "europe",
        label: "Europe",
        country_code: "europe",
        pbf_urls: ["http://example.test/europe-latest.osm.pbf"]
      }
    }
  end

  defp start_applier(tmp, opts \\ []) do
    test_pid = self()

    downloader =
      Keyword.get(opts, :downloader, fn url, dest, progress_fun ->
        File.mkdir_p!(Path.dirname(dest))
        File.write!(dest, "data:#{url}")
        progress_fun.(100, 200)
        {:ok, dest}
      end)

    osmium_merge =
      Keyword.get(opts, :osmium_merge, fn dir, sources, out ->
        send(test_pid, {:merge, dir, sources, out})
        File.write!(Path.expand(out, dir), "merged")
        {:ok, "ok"}
      end)

    osmium_convert =
      Keyword.get(opts, :osmium_convert, fn dir, in_path, out ->
        send(test_pid, {:convert, dir, in_path, out})
        File.write!(Path.expand(out, dir), "bz2")
        {:ok, "ok"}
      end)

    restart =
      Keyword.get(opts, :restart, fn names ->
        send(test_pid, {:restart, names})
        :ok
      end)

    start_supervised!(
      {RegionApplier,
       data_dir: tmp,
       downloader: downloader,
       osmium_merge: osmium_merge,
       osmium_convert: osmium_convert,
       restart: restart,
       enabled?: Keyword.get(opts, :enabled?, fn _name -> true end),
       catalog_find: fn name -> Map.get(catalog(), name) end}
    )

    Phoenix.PubSub.subscribe(Atlas.PubSub, @topic)
  end

  setup do
    tmp = Path.join(System.tmp_dir!(), "applier-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "overpass source conversion" do
    test "a failed convert removes the orphaned .partial", %{tmp: tmp} do
      start_applier(tmp,
        osmium_convert: fn dir, _in_path, out ->
          File.write!(Path.expand(out, dir), "half-written")
          {:error, 1, "osmium: killed"}
        end
      )

      assert {:ok, job_id} = RegionApplier.start(["berlin"])
      assert_receive {:apply_error, %{job_id: ^job_id}}, 2_000

      refute File.exists?(Path.join(tmp, "osm/current.osm.bz2.partial")),
             "orphaned .partial must be cleaned up, not left to accumulate"
    end

    test "a failed convert fails the apply loudly instead of keeping stale data", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "osm"))
      stale = Path.join(tmp, "osm/current.osm.bz2")
      File.write!(stale, "seven-weeks-old")

      start_applier(tmp,
        osmium_convert: fn _dir, _in_path, _out -> {:error, 1, "osmium: killed"} end
      )

      assert {:ok, job_id} = RegionApplier.start(["berlin"])

      assert_receive {:apply_error, %{job_id: ^job_id, phase: :converting, reason: reason}}, 2_000
      assert reason =~ "osmium: killed"

      assert File.read!(stale) == "seven-weeks-old",
             "the stale bz2 stays on disk, but the apply reports failure rather than " <>
               "letting overpass silently re-import it as if it were fresh"

      assert_received {:restart, services}
      refute "overpass" in services
    end

    test "a successful convert still promotes .partial to the real bz2", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "osm"))
      File.write!(Path.join(tmp, "osm/current.osm.bz2"), "seven-weeks-old")

      start_applier(tmp)

      assert {:ok, job_id} = RegionApplier.start(["berlin"])
      assert_receive {:apply_done, %{job_id: ^job_id}}, 2_000

      assert File.read!(Path.join(tmp, "osm/current.osm.bz2")) == "bz2"
      refute File.exists?(Path.join(tmp, "osm/current.osm.bz2.partial"))
    end

    test "a failed convert still stages OTP and restarts the other ingest services",
         %{tmp: tmp} do
      start_applier(tmp,
        osmium_convert: fn _dir, _in_path, _out -> {:error, 1, "osmium: killed"} end
      )

      assert {:ok, job_id} = RegionApplier.start(["berlin"])
      assert_receive {:apply_error, %{job_id: ^job_id, phase: :converting}}, 2_000

      assert File.exists?(Path.join(tmp, "otp/region.osm.pbf")),
             "a broken overpass source must not withhold the fresh PBF from OTP"

      assert_received {:apply_restarting, ["valhalla", "motis"]},
                      "the timeline must be told exactly which services are being restarted"

      assert_received {:restart, services},
                      "valhalla/otp got new data and must still be restarted"

      refute "overpass" in services,
             "overpass must NOT be restarted onto a source that failed to convert"
    end

    test "orphaned .partial files from a previous run are swept at apply start", %{tmp: tmp} do
      osm = Path.join(tmp, "osm")
      File.mkdir_p!(osm)
      File.write!(Path.join(osm, "current.osm.bz2.partial"), "interrupted")
      File.write!(Path.join(osm, "current.osm.pbf.partial"), "interrupted")

      start_applier(tmp)

      assert {:ok, job_id} = RegionApplier.start(["berlin"])
      assert_receive {:apply_done, %{job_id: ^job_id}}, 2_000

      refute File.exists?(Path.join(osm, "current.osm.pbf.partial"))

      assert File.read!(Path.join(osm, "current.osm.bz2")) == "bz2"
    end

    test "the sweep also clears interrupted downloads under sources/ and gtfs/", %{tmp: tmp} do
      osm = Path.join(tmp, "osm")
      sources = Path.join(osm, "sources")
      gtfs = Path.join(tmp, "gtfs")
      File.mkdir_p!(sources)
      File.mkdir_p!(gtfs)

      # A killed download leaves a multi-hundred-MB .partial; the downloader
      # truncates on retry rather than resuming, so it is pure garbage.
      File.write!(Path.join(sources, "berlin-latest.osm.pbf.partial"), "interrupted")
      File.write!(Path.join(gtfs, "vbb.gtfs.zip.partial"), "interrupted")

      start_applier(tmp)

      assert {:ok, job_id} = RegionApplier.start(["berlin"])
      assert_receive {:apply_done, %{job_id: ^job_id}}, 2_000

      refute File.exists?(Path.join(sources, "berlin-latest.osm.pbf.partial"))
      refute File.exists?(Path.join(gtfs, "vbb.gtfs.zip.partial"))
    end
  end

  test "single region: download, symlink, convert, stage otp, restart", %{tmp: tmp} do
    File.mkdir_p!(Path.join(tmp, "otp"))
    File.write!(Path.join(tmp, "otp/graph.obj"), "stale")

    for name <-
          ~w(file_hashes.txt .file_hashes.txt valhalla_tiles.tar valhalla_tiles/old.gph admin_data/admins.sqlite) do
      path = Path.join([tmp, "valhalla", name])
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "stale")
    end

    start_applier(tmp)

    assert {:ok, job_id} = RegionApplier.start(["berlin"])

    assert_receive {:apply_done, %{job_id: ^job_id, regions: ["berlin"]}}, 2_000

    assert_received {:apply_start, %{job_id: ^job_id, regions: ["berlin"]}}
    assert_received {:apply_progress, %{job_id: ^job_id, phase: :downloading, region: "berlin"}}

    sources = Path.join(tmp, "osm/sources/berlin-latest.osm.pbf")
    assert File.read!(sources) == "data:http://example.test/berlin-latest.osm.pbf"

    current = Path.join(tmp, "osm/current.osm.pbf")
    assert File.read_link!(current) == "sources/berlin-latest.osm.pbf"

    assert_received {:convert, _, "current.osm.pbf", "current.osm.bz2.partial"}
    assert File.exists?(Path.join(tmp, "osm/current.osm.bz2"))

    assert File.read!(Path.join(tmp, "otp/region.osm.pbf")) ==
             "data:http://example.test/berlin-latest.osm.pbf"

    # Valhalla's image scans its own /custom_files for *.osm.pbf and refuses to
    # start without one ("No local PBF files... Nothing to do"). Mounting the
    # osm dir elsewhere does not help — the file has to land here.
    assert File.read!(Path.join(tmp, "valhalla/region.osm.pbf")) ==
             "data:http://example.test/berlin-latest.osm.pbf"

    assert File.exists?(Path.join(tmp, "gtfs/vbb.gtfs.zip"))
    assert File.exists?(Path.join(tmp, "otp/vbb.gtfs.zip"))
    refute File.exists?(Path.join(tmp, "otp/graph.obj"))

    for name <- ~w(file_hashes.txt .file_hashes.txt valhalla_tiles.tar valhalla_tiles admin_data) do
      refute File.exists?(Path.join([tmp, "valhalla", name]))
    end

    assert_received {:apply_restarting, ["valhalla", "overpass", "motis"]}
    assert_received {:restart, ["valhalla", "overpass", "motis"]}

    assert RegionApplier.status() == nil
  end

  test "only services that will actually restart are announced", %{tmp: tmp} do
    # The timeline builds its sidecar rows from this broadcast. Naming a service
    # that is switched off gives it a row that can never start, which the
    # timeline then has to guess about.
    start_applier(tmp, enabled?: fn name -> name != "overpass" end)

    assert {:ok, job_id} = RegionApplier.start(["berlin"])
    assert_receive {:apply_done, %{job_id: ^job_id}}, 2_000

    assert_received {:apply_restarting, ["valhalla", "motis"]}
    assert_received {:restart, ["valhalla", "motis"]}
  end

  test "staging pins OTP's time zone when the regions agree on one", %{tmp: tmp} do
    start_applier(tmp)

    assert {:ok, job_id} = RegionApplier.start(["berlin", "bayern"])
    assert_receive {:apply_done, %{job_id: ^job_id}}, 2_000

    assert %{"osmDefaults" => %{"timeZone" => "Europe/Berlin"}} =
             tmp |> Path.join("otp/build-config.json") |> File.read!() |> Jason.decode!()
  end

  test "a restart failure is recorded even when the convert already failed", %{tmp: tmp} do
    # The convert-failure path restarts valhalla/otp and returned the convert
    # error, discarding the restart result — so a restart that never happened
    # went unrecorded and those rows still went green off the old container.
    start_applier(tmp,
      osmium_convert: fn _dir, _in, _out -> {:error, 1, "osmium: killed"} end,
      restart: fn _names -> {:error, "docker daemon gone"} end
    )

    assert {:ok, job_id} = RegionApplier.start(["berlin"])
    assert_receive {:apply_error, %{job_id: ^job_id, phase: :converting}}, 2_000

    assert_received {:apply_error, %{phase: :restarting, reason: restart_reason}}
    assert restart_reason =~ "docker daemon gone"
  end

  test "a failed restart fails the apply instead of reporting success", %{tmp: tmp} do
    start_applier(tmp, restart: fn _names -> {:error, "docker daemon gone"} end)

    assert {:ok, job_id} = RegionApplier.start(["berlin"])

    assert_receive {:apply_error, %{job_id: ^job_id, phase: :restarting, reason: reason}}, 2_000
    assert reason =~ "docker daemon gone"
  end

  test "staging reports which time zone it pinned", %{tmp: tmp} do
    start_applier(tmp)

    assert {:ok, job_id} = RegionApplier.start(["berlin"])
    assert_receive {:apply_done, %{job_id: ^job_id}}, 2_000

    assert_received {:apply_progress, %{phase: :staging, detail: "time zone Europe/Berlin"}}
  end

  test "staging says so when no time zone could be pinned", %{tmp: tmp} do
    start_applier(tmp)

    assert {:ok, job_id} = RegionApplier.start(["berlin", "kent"])
    assert_receive {:apply_done, %{job_id: ^job_id}}, 2_000

    assert_received {:apply_progress, %{phase: :staging, detail: detail}}
    assert detail =~ "no time zone"
  end

  test "staging writes no build config when the regions disagree", %{tmp: tmp} do
    start_applier(tmp)

    assert {:ok, job_id} = RegionApplier.start(["berlin", "kent"])
    assert_receive {:apply_done, %{job_id: ^job_id}}, 2_000

    refute File.exists?(Path.join(tmp, "otp/build-config.json")),
           "CET and GMT cannot both be right; OTP's warning beats a wrong answer"
  end

  test "staging clears a stale build config rather than leaving it", %{tmp: tmp} do
    # A previous Germany-only apply pinned Europe/Berlin. Applying a region that
    # resolves to nothing must not inherit it — OTP would shift every opening
    # hour in the new extract by whole hours, silently.
    File.mkdir_p!(Path.join(tmp, "otp"))

    File.write!(
      Path.join(tmp, "otp/build-config.json"),
      ~s({"osmDefaults":{"timeZone":"Europe/Berlin"}})
    )

    start_applier(tmp)

    assert {:ok, job_id} = RegionApplier.start(["europe"])
    assert_receive {:apply_done, %{job_id: ^job_id}}, 2_000

    refute File.exists?(Path.join(tmp, "otp/build-config.json"))
  end

  test "download progress names the file, its source URL and byte counts", %{tmp: tmp} do
    downloader = fn _url, dest, progress_fun ->
      File.mkdir_p!(Path.dirname(dest))
      File.write!(dest, "pbf")
      progress_fun.(512, 2048)
      {:ok, dest}
    end

    start_applier(tmp, downloader: downloader)
    assert {:ok, job_id} = RegionApplier.start(["berlin"])

    assert_receive {:apply_progress,
                    %{
                      phase: :downloading,
                      item: %{
                        label: "berlin-latest.osm.pbf",
                        source: "http://example.test/berlin-latest.osm.pbf",
                        current: 512,
                        total: 2048
                      }
                    }},
                   2_000

    # Wait for the pipeline to finish so the background Task isn't still
    # writing into `tmp` when `on_exit` tries to remove it (see the other
    # tests in this file, all of which wait out the full run).
    assert_receive {:apply_done, %{job_id: ^job_id}}, 2_000
  end

  test "two regions merge instead of symlink", %{tmp: tmp} do
    start_applier(tmp)

    assert {:ok, job_id} = RegionApplier.start(["berlin", "bayern"])
    assert_receive {:apply_done, %{job_id: ^job_id}}, 2_000

    assert_received {:merge, dir, sources, "../current.osm.pbf.partial"}
    assert dir == Path.join(tmp, "osm/sources")
    assert sources == ["berlin-latest.osm.pbf", "bayern-latest.osm.pbf"]

    assert File.read!(Path.join(tmp, "osm/current.osm.pbf")) == "merged"
  end

  test "download failure broadcasts apply_error and persists in status", %{tmp: tmp} do
    start_applier(tmp,
      downloader: fn _url, _dest, _progress -> {:error, {:http_status, 500}} end
    )

    assert {:ok, job_id} = RegionApplier.start(["bayern"])

    assert_receive {:apply_error, %{job_id: ^job_id, phase: :downloading, reason: reason}}, 2_000
    assert reason =~ "500"

    assert %{job_id: ^job_id, error: err, phase: :downloading} = RegionApplier.status()
    assert err =~ "500"

    refute File.exists?(Path.join(tmp, "osm/current.osm.pbf"))
  end

  test "gtfs download failure is non-fatal", %{tmp: tmp} do
    start_applier(tmp,
      downloader: fn url, dest, progress_fun ->
        if String.ends_with?(url, ".zip") do
          {:error, {:http_status, 503}}
        else
          File.mkdir_p!(Path.dirname(dest))
          File.write!(dest, "pbf")
          progress_fun.(1, 1)
          {:ok, dest}
        end
      end
    )

    assert {:ok, job_id} = RegionApplier.start(["berlin"])
    assert_receive {:apply_done, %{job_id: ^job_id}}, 2_000

    refute File.exists?(Path.join(tmp, "gtfs/vbb.gtfs.zip"))
  end

  test "unknown region fails fast without a job", %{tmp: tmp} do
    start_applier(tmp)

    assert {:error, {:region_not_found, "atlantis"}} = RegionApplier.start(["berlin", "atlantis"])
    refute_receive {:apply_start, _}, 100
  end

  test "lifecycle is visible in the app log (docker logs)", %{tmp: tmp} do
    import ExUnit.CaptureLog

    previous_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous_level) end)

    log =
      capture_log(fn ->
        start_applier(tmp)
        {:ok, _job_id} = RegionApplier.start(["berlin"])
        assert_receive {:apply_done, _}, 2_000
        Process.sleep(50)
      end)

    assert log =~ "region apply started: berlin"
    assert log =~ "region apply finished: berlin"
  end

  test "failures are visible in the app log", %{tmp: tmp} do
    import ExUnit.CaptureLog

    log =
      capture_log(fn ->
        start_applier(tmp,
          downloader: fn _url, _dest, _progress -> {:error, {:http_status, 500}} end
        )

        {:ok, _job_id} = RegionApplier.start(["bayern"])
        assert_receive {:apply_error, _}, 2_000
        Process.sleep(50)
      end)

    assert log =~ "region apply failed"
    assert log =~ "500"
  end

  test "second start while busy returns busy", %{tmp: tmp} do
    test_pid = self()

    start_applier(tmp,
      downloader: fn _url, dest, _progress ->
        send(test_pid, {:downloading, self()})

        receive do
          :proceed -> :ok
        after
          2_000 -> :ok
        end

        File.mkdir_p!(Path.dirname(dest))
        File.write!(dest, "pbf")
        {:ok, dest}
      end
    )

    assert {:ok, _job_id} = RegionApplier.start(["bayern"])
    assert_receive {:downloading, dl_pid}, 1_000

    assert {:error, :busy} = RegionApplier.start(["berlin"])

    send(dl_pid, :proceed)
    assert_receive {:apply_done, _}, 2_000
  end

  describe "summarize_restarts/1" do
    test "reports every failure, not just the first" do
      # reduce_while halted on the first bad compose call, leaving the rest of
      # the sidecars unrestarted with no record of which.
      results = [
        {"valhalla", {:error, 1, "no such service\n"}},
        {"overpass", {:ok, ""}},
        {"otp", {:error, 137, "OOMKilled\n"}}
      ]

      assert {:error, message} = RegionApplier.summarize_restarts(results)
      assert message =~ "valhalla"
      assert message =~ "otp"
      refute message =~ "overpass"
    end

    test "all good is plain :ok" do
      assert RegionApplier.summarize_restarts([{"valhalla", {:ok, ""}}]) == :ok
      assert RegionApplier.summarize_restarts([]) == :ok
    end
  end
end
