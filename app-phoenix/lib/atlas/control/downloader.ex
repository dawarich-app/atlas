defmodule Atlas.Control.Downloader do
  @moduledoc """
  Streaming HTTP downloads for large artifacts (region PBFs, GTFS bundles,
  basemap tile packs).

  Bytes stream straight to `<dest>.partial` and the file is renamed into
  place only on success, so consumers never observe a truncated download.
  `progress_fun.(bytes_so_far, total_bytes_or_nil)` fires throttled (every
  ~1 MB) with the total taken from `Content-Length` when the server sends it.

  Returns `{:ok, dest}`, `{:ok, :cached}` when `dest` already exists, or
  `{:error, reason}` (with no partial file left behind).
  """

  @progress_step_bytes 1_000_000

  def fetch(url, dest, progress_fun) when is_function(progress_fun, 2) do
    if File.exists?(dest) do
      {:ok, :cached}
    else
      do_fetch(url, dest, progress_fun)
    end
  end

  defp do_fetch(url, dest, progress_fun) do
    partial = dest <> ".partial"
    File.mkdir_p!(Path.dirname(dest))
    file = File.open!(partial, [:write, :binary])
    counters = :counters.new(2, [])

    result =
      Req.get(url,
        retry: false,
        raw: true,
        into: fn {:data, chunk}, {req, resp} ->
          if resp.status == 200 do
            IO.binwrite(file, chunk)
            report_progress(counters, byte_size(chunk), total_bytes(resp), progress_fun)
          end

          {:cont, {req, resp}}
        end
      )

    File.close(file)

    case result do
      {:ok, %Req.Response{status: 200} = resp} ->
        File.rename!(partial, dest)
        progress_fun.(:counters.get(counters, 1), total_bytes(resp))
        {:ok, dest}

      {:ok, %Req.Response{status: status}} ->
        File.rm(partial)
        {:error, {:http_status, status}}

      {:error, reason} ->
        File.rm(partial)
        {:error, reason}
    end
  end

  defp report_progress(counters, chunk_size, total, progress_fun) do
    :counters.add(counters, 1, chunk_size)
    bytes = :counters.get(counters, 1)
    last_reported = :counters.get(counters, 2)

    if bytes - last_reported >= @progress_step_bytes do
      :counters.put(counters, 2, bytes)
      progress_fun.(bytes, total)
    end
  end

  defp total_bytes(resp) do
    case Req.Response.get_header(resp, "content-length") do
      [len | _] ->
        case Integer.parse(len) do
          {n, _} -> n
          :error -> nil
        end

      _ ->
        nil
    end
  end
end
