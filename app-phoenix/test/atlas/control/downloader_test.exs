defmodule Atlas.Control.DownloaderTest do
  use ExUnit.Case, async: false

  alias Atlas.Control.Downloader

  @body String.duplicate("x", 50_000)

  setup do
    bypass = Bypass.open()
    tmp = Path.join(System.tmp_dir!(), "downloader-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, bypass: bypass, tmp: tmp}
  end

  defp url(bypass, path), do: "http://localhost:#{bypass.port}#{path}"

  test "streams body to dest via .partial and reports byte progress", %{bypass: bypass, tmp: tmp} do
    Bypass.expect_once(bypass, "GET", "/file.pbf", fn conn ->
      Plug.Conn.resp(conn, 200, @body)
    end)

    dest = Path.join(tmp, "file.pbf")
    test_pid = self()

    assert {:ok, ^dest} =
             Downloader.fetch(url(bypass, "/file.pbf"), dest, fn bytes, total ->
               send(test_pid, {:progress, bytes, total})
             end)

    assert File.read!(dest) == @body
    refute File.exists?(dest <> ".partial")

    assert_received {:progress, bytes, total} when is_integer(bytes)
    assert total == byte_size(@body) or is_nil(total)
  end

  test "skips download when dest already exists", %{bypass: bypass, tmp: tmp} do
    dest = Path.join(tmp, "cached.pbf")
    File.write!(dest, "already here")

    assert {:ok, :cached} = Downloader.fetch(url(bypass, "/cached.pbf"), dest, fn _, _ -> :ok end)
    assert File.read!(dest) == "already here"
  end

  test "non-200 response returns error and leaves no partial file", %{bypass: bypass, tmp: tmp} do
    Bypass.expect_once(bypass, "GET", "/missing.pbf", fn conn ->
      Plug.Conn.resp(conn, 404, "not found")
    end)

    dest = Path.join(tmp, "missing.pbf")

    assert {:error, {:http_status, 404}} =
             Downloader.fetch(url(bypass, "/missing.pbf"), dest, fn _, _ -> :ok end)

    refute File.exists?(dest)
    refute File.exists?(dest <> ".partial")
  end

  test "transport error returns error and leaves no partial file", %{bypass: bypass, tmp: tmp} do
    Bypass.down(bypass)
    dest = Path.join(tmp, "down.pbf")

    assert {:error, _reason} = Downloader.fetch(url(bypass, "/down.pbf"), dest, fn _, _ -> :ok end)

    refute File.exists?(dest)
    refute File.exists?(dest <> ".partial")
  end
end
