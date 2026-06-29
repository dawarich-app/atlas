defmodule Atlas.Control.RegionApplierTest do
  use ExUnit.Case, async: false

  alias Atlas.Control.{RegionApplier, RegionCatalog}

  @topic "control:apply"

  defp catalog do
    %{
      "berlin" => %RegionCatalog{
        name: "berlin",
        label: "Berlin",
        pbf_urls: ["http://example.test/berlin-latest.osm.pbf"],
        gtfs_url: "http://example.test/vbb.zip",
        gtfs_name: "vbb.gtfs.zip"
      },
      "bayern" => %RegionCatalog{
        name: "bayern",
        label: "Bayern",
        pbf_urls: ["http://example.test/bayern-latest.osm.pbf"]
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

  test "single region: download, symlink, convert, stage otp, restart", %{tmp: tmp} do
    File.mkdir_p!(Path.join(tmp, "otp"))
    File.write!(Path.join(tmp, "otp/graph.obj"), "stale")

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

    assert File.exists?(Path.join(tmp, "gtfs/vbb.gtfs.zip"))
    assert File.exists?(Path.join(tmp, "otp/vbb.gtfs.zip"))
    refute File.exists?(Path.join(tmp, "otp/graph.obj"))

    assert_received {:restart, ["valhalla", "overpass", "otp"]}

    assert RegionApplier.status() == nil
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
        start_applier(tmp, downloader: fn _url, _dest, _progress -> {:error, {:http_status, 500}} end)
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
end
