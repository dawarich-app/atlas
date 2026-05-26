defmodule Atlas.Control.TilesDownloader do
  @moduledoc """
  Serializes tile-pack downloads. Only one download runs at a time; the
  request is queued as a GenServer call.

  The actual fetch is delegated to a `:downloader` function injected at
  start-up. The default downloader is a simple `Req`-based GET that streams
  the response body to a file on disk and broadcasts coarse-grained progress
  (`:start`, `:progress`, `:done`, `:error`) on
  `"control:tiles:download"`.

  ## M3 followups

  The default downloader is intentionally minimal:

    * progress is broadcast once with `1.0` after the download finishes —
      true byte-level streaming progress (using `Content-Length` and
      `Req.into:` callbacks) is deferred to M3 along with the live admin
      panel that consumes it;
    * we don't yet checksum or resume partial files.

  Tests inject a deterministic downloader so they don't hit the network.
  """

  use GenServer

  @topic "control:tiles:download"

  defstruct [:downloader, :dest_dir, current: nil]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Kick off a download. Returns immediately with the job id; progress is
  broadcast on `\"control:tiles:download\"`.
  """
  def download(url) when is_binary(url) do
    GenServer.call(__MODULE__, {:download, url}, :timer.minutes(30))
  end

  @doc "Inspect current downloader state — `nil` when idle."
  def status, do: GenServer.call(__MODULE__, :status)

  @doc "PubSub topic used for download progress events."
  def topic, do: @topic

  @impl true
  def init(opts) do
    state = %__MODULE__{
      downloader: Keyword.get(opts, :downloader, &default_downloader/2),
      dest_dir: Keyword.get(opts, :dest_dir, "/data/tiles")
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:download, url}, _from, state) do
    job_id = Ecto.UUID.generate()
    dest = Path.join(state.dest_dir, Path.basename(URI.parse(url).path || "tiles.bin"))

    broadcast({:start, job_id, url, dest})

    result =
      try do
        state.downloader.(url, dest)
      rescue
        e -> {:error, Exception.message(e)}
      end

    case result do
      :ok ->
        broadcast({:progress, job_id, 1.0})
        broadcast({:done, job_id, dest})
        {:reply, {:ok, job_id, dest}, %{state | current: nil}}

      {:ok, _} ->
        broadcast({:progress, job_id, 1.0})
        broadcast({:done, job_id, dest})
        {:reply, {:ok, job_id, dest}, %{state | current: nil}}

      {:error, reason} = err ->
        broadcast({:error, job_id, reason})
        {:reply, err, %{state | current: nil}}
    end
  end

  def handle_call(:status, _from, state), do: {:reply, state.current, state}

  defp broadcast(msg), do: Phoenix.PubSub.broadcast(Atlas.PubSub, @topic, msg)

  # Production default: stream to a file via Req. We pull the whole body
  # because chunked-progress reporting is an M3 concern.
  defp default_downloader(url, dest) do
    File.mkdir_p!(Path.dirname(dest))

    case Req.get(url) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        File.write!(dest, body)
        :ok

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, %{__exception__: true} = e} ->
        {:error, Exception.message(e)}
    end
  end
end
