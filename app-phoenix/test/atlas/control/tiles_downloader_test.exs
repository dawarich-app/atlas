defmodule Atlas.Control.TilesDownloaderTest do
  use ExUnit.Case, async: false

  alias Atlas.Control.TilesDownloader

  setup do
    test_pid = self()

    downloader = fn url, dest ->
      send(test_pid, {:download_called, url, dest})
      :ok
    end

    {:ok, pid} =
      start_supervised({TilesDownloader, downloader: downloader, dest_dir: "/tmp/atlas-tiles-test"})

    {:ok, pid: pid}
  end

  test "download/1 invokes the injected downloader and broadcasts :start, :done" do
    Phoenix.PubSub.subscribe(Atlas.PubSub, TilesDownloader.topic())

    assert {:ok, job_id, dest} = TilesDownloader.download("https://example.com/path/tiles.json")

    assert is_binary(job_id)
    assert String.ends_with?(dest, "tiles.json")
    assert_received {:download_called, "https://example.com/path/tiles.json", ^dest}

    assert_receive {:start, ^job_id, "https://example.com/path/tiles.json", ^dest}
    assert_receive {:progress, ^job_id, 1.0}
    assert_receive {:done, ^job_id, ^dest}
  end

  test "downloader error is surfaced and broadcast" do
    test_pid = self()

    failing = fn _url, _dest ->
      send(test_pid, :failing_invoked)
      {:error, "boom"}
    end

    stop_supervised!(TilesDownloader)
    {:ok, _} = start_supervised({TilesDownloader, downloader: failing, dest_dir: "/tmp/x"})

    Phoenix.PubSub.subscribe(Atlas.PubSub, TilesDownloader.topic())

    assert {:error, "boom"} = TilesDownloader.download("https://example.com/x")
    assert_received :failing_invoked
    assert_receive {:error, _job_id, "boom"}
  end
end
