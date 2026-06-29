defmodule Atlas.Control.TilesDownloader do
  @moduledoc """
  Asynchronous tile-pack downloads. `download/1` validates and returns
  `{:ok, job_id, dest}` immediately; the fetch runs in a `Task` (so a
  planet-scale pack is not bounded by a `GenServer.call` timeout) and only
  one download runs at a time — a second request gets `{:error, :busy}`.

  Bytes stream via `Atlas.Control.Downloader.fetch/3`, so progress events
  carry real byte fractions. Lifecycle events broadcast on
  `"control:tiles:download"`:

      {:start,    job_id, url, dest}
      {:progress, job_id, fraction}
      {:done,     job_id, dest}
      {:error,    job_id, reason}

  `status/0` is refresh-proof: it returns the running job, or the sticky
  last result (`:done` / `:error`) until the next download starts.

  The destination dir defaults to `/work/data/tiles`, which compose binds to
  `./data/tiles` — the directory Caddy serves at `/tiles/*`. `on_success`
  (default: persist the served URL as the active basemap) runs after a
  completed download.
  """

  use GenServer

  require Logger

  @topic "control:tiles:download"

  defstruct [:downloader, :dest_dir, :on_success, current: nil, last_result: nil]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Kick off a download. Returns `{:ok, job_id, dest}` as soon as the job is
  accepted, or `{:error, :busy}` while another download runs.
  """
  def download(url) when is_binary(url) do
    GenServer.call(__MODULE__, {:download, url})
  end

  @doc """
  Running job (`%{status: :running, ...}`), sticky last result
  (`%{status: :done | :error, ...}`), or `nil`.
  """
  def status, do: GenServer.call(__MODULE__, :status)

  @doc "PubSub topic used for download progress events."
  def topic, do: @topic

  @doc "Browser-reachable URL for a downloaded pack (served by Caddy)."
  def public_url(dest), do: "/tiles/" <> Path.basename(dest)

  @doc """
  HEAD the URL and report its `Content-Length` so the UI can confirm
  multi-GB downloads before starting them. `{:ok, nil}` when the server
  doesn't say.
  """
  def probe_size(url) do
    case Req.head(url, retry: false) do
      {:ok, %Req.Response{status: status} = resp} when status in 200..299 ->
        {:ok, content_length(resp)}

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, %{__exception__: true} = e} ->
        {:error, Exception.message(e)}
    end
  end

  defp content_length(resp) do
    with [len | _] <- Req.Response.get_header(resp, "content-length"),
         {n, _} <- Integer.parse(len) do
      n
    else
      _ -> nil
    end
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      downloader: Keyword.get(opts, :downloader, &Atlas.Control.Downloader.fetch/3),
      dest_dir: Keyword.get(opts, :dest_dir, "/work/data/tiles"),
      on_success: Keyword.get(opts, :on_success, &default_on_success/2)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:download, url}, _from, state) do
    if state.current do
      {:reply, {:error, :busy}, state}
    else
      job_id = Ecto.UUID.generate()
      dest = Path.join(state.dest_dir, Path.basename(URI.parse(url).path || "tiles.bin"))

      broadcast({:start, job_id, url, dest})
      Logger.info("tiles download started: #{url} -> #{dest} (job #{job_id})")

      parent = self()

      Task.start(fn ->
        result =
          try do
            state.downloader.(url, dest, fn bytes, total ->
              send(parent, {:dl_progress, job_id, bytes, total})
            end)
          rescue
            e -> {:error, e}
          catch
            :exit, reason -> {:error, {:exit, reason}}
          end

        send(parent, {:dl_done, job_id, url, dest, result})
      end)

      current = %{status: :running, job_id: job_id, url: url, dest: dest, progress: 0.0}
      {:reply, {:ok, job_id, dest}, %{state | current: current}}
    end
  end

  def handle_call(:status, _from, state) do
    {:reply, state.current || state.last_result, state}
  end

  @impl true
  def handle_info({:dl_progress, job_id, bytes, total}, state) do
    case state.current do
      %{job_id: ^job_id} = current ->
        fraction = if is_integer(total) and total > 0, do: bytes / total, else: 0.0
        broadcast({:progress, job_id, fraction})

        # One log line per whole percent — visible in `docker logs` without
        # flooding it (a planet pack emits ~100 lines total).
        if trunc(fraction * 100) > trunc(current.progress * 100) do
          Logger.info(
            "tiles download progress: #{trunc(fraction * 100)}% " <>
              "(#{div(bytes, 1_000_000)} MB / #{div(total, 1_000_000)} MB)"
          )
        end

        {:noreply, %{state | current: %{current | progress: fraction}}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:dl_done, job_id, url, dest, result}, state) do
    last =
      case result do
        {:ok, _} ->
          state.on_success.(url, dest)
          broadcast({:progress, job_id, 1.0})
          broadcast({:done, job_id, dest})
          Logger.info("tiles download finished: #{dest}")
          %{status: :done, job_id: job_id, dest: dest, progress: 1.0}

        {:error, reason} ->
          message = format_reason(reason)
          broadcast({:error, job_id, message})
          Logger.warning("tiles download failed: #{url} — #{message}")
          %{status: :error, job_id: job_id, url: url, reason: message}
      end

    {:noreply, %{state | current: nil, last_result: last}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp broadcast(msg), do: Phoenix.PubSub.broadcast(Atlas.PubSub, @topic, msg)

  defp default_on_success(_url, dest) do
    Atlas.Settings.set("tiles_url", public_url(dest))
    :ok
  end

  defp format_reason({:http_status, status}), do: "HTTP #{status}"
  defp format_reason(%{__exception__: true} = e), do: Exception.message(e)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(other), do: inspect(other)
end
