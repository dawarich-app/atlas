defmodule Atlas.Control.TilesDownloaderTest do
  use ExUnit.Case, async: false

  alias Atlas.Control.TilesDownloader

  defp start_downloader(opts) do
    defaults = [dest_dir: "/tmp/atlas-tiles-test", on_success: fn _url, _dest -> :ok end]
    start_supervised!({TilesDownloader, Keyword.merge(defaults, opts)})
  end

  test "download/1 returns immediately and streams progress to done" do
    test_pid = self()

    downloader = fn url, dest, progress_fun ->
      send(test_pid, {:download_called, url, dest})
      progress_fun.(50, 100)
      progress_fun.(100, 100)
      {:ok, dest}
    end

    start_downloader(downloader: downloader)
    Phoenix.PubSub.subscribe(Atlas.PubSub, TilesDownloader.topic())

    assert {:ok, job_id, dest} = TilesDownloader.download("https://example.com/path/tiles.pmtiles")
    assert String.ends_with?(dest, "tiles.pmtiles")

    assert_receive {:start, ^job_id, "https://example.com/path/tiles.pmtiles", ^dest}, 1_000
    assert_receive {:progress, ^job_id, 0.5}, 1_000
    assert_receive {:done, ^job_id, ^dest}, 1_000

    assert %{status: :done, dest: ^dest} = TilesDownloader.status()
  end

  test "second download while one runs returns busy" do
    test_pid = self()

    downloader = fn _url, dest, _progress ->
      send(test_pid, {:started, self()})

      receive do
        :proceed -> :ok
      after
        2_000 -> :ok
      end

      {:ok, dest}
    end

    start_downloader(downloader: downloader)
    Phoenix.PubSub.subscribe(Atlas.PubSub, TilesDownloader.topic())

    assert {:ok, _job_id, _dest} = TilesDownloader.download("https://example.com/a.pmtiles")
    assert_receive {:started, dl_pid}, 1_000

    assert {:error, :busy} = TilesDownloader.download("https://example.com/b.pmtiles")
    assert %{status: :running} = TilesDownloader.status()

    send(dl_pid, :proceed)
    assert_receive {:done, _, _}, 2_000
  end

  test "downloader error is broadcast and kept in status" do
    start_downloader(downloader: fn _url, _dest, _progress -> {:error, {:http_status, 503}} end)
    Phoenix.PubSub.subscribe(Atlas.PubSub, TilesDownloader.topic())

    assert {:ok, job_id, _dest} = TilesDownloader.download("https://example.com/x.pmtiles")

    assert_receive {:error, ^job_id, reason}, 1_000
    assert reason =~ "503"

    assert %{status: :error, reason: kept} = TilesDownloader.status()
    assert kept =~ "503"
  end

  test "on_success callback runs after a completed download" do
    test_pid = self()

    start_downloader(
      downloader: fn _url, dest, _progress -> {:ok, dest} end,
      on_success: fn url, dest -> send(test_pid, {:succeeded, url, dest}) end
    )

    assert {:ok, _job_id, dest} = TilesDownloader.download("https://example.com/ok.pmtiles")
    assert_receive {:succeeded, "https://example.com/ok.pmtiles", ^dest}, 1_000
  end

  test "public_url/1 maps a dest path to the Caddy-served /tiles route" do
    assert TilesDownloader.public_url("/work/data/tiles/basemap.pmtiles") ==
             "/tiles/basemap.pmtiles"
  end

  test "lifecycle is visible in the app log (docker logs)" do
    import ExUnit.CaptureLog

    previous_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous_level) end)

    log =
      capture_log(fn ->
        start_downloader(downloader: fn _url, dest, _progress -> {:ok, dest} end)
        {:ok, _job, _dest} = TilesDownloader.download("https://example.com/pack.pmtiles")
        Process.sleep(100)
      end)

    assert log =~ "tiles download started"
    assert log =~ "https://example.com/pack.pmtiles"
    assert log =~ "tiles download finished"
  end

  test "failures are visible in the app log" do
    import ExUnit.CaptureLog

    log =
      capture_log(fn ->
        start_downloader(
          downloader: fn _url, _dest, _progress -> {:error, {:http_status, 503}} end
        )

        {:ok, _job, _dest} = TilesDownloader.download("https://example.com/pack.pmtiles")
        Process.sleep(100)
      end)

    assert log =~ "tiles download failed"
    assert log =~ "503"
  end
end
