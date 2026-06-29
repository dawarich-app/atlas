defmodule AtlasWeb.Admin.ServiceLogsLive do
  @moduledoc ~S"""
  Streaming log viewer for one service.

  Subscribes to `"logs:#{name}"` and starts (or reuses) an
  `Atlas.Control.LogTailer` for that service via the dynamic supervisor.
  Lines arrive as `{:log_line, binary}` and are appended to a LiveView
  stream capped at `@max_buffered_lines`; `{:log_eof, code}` marks the end
  of the stream instead of leaving a silently frozen panel.

  The `LogStream` JS hook auto-scrolls the container on each insert.
  """
  use AtlasWeb, :live_view

  @max_buffered_lines 500

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    tailer =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Atlas.PubSub, "logs:#{name}")
        safe_start_tailer(name)
      else
        :ok
      end

    # Replay the buffer of an already-running tailer (attached at boot) so
    # the viewer doesn't sit empty on a quiet service.
    recent =
      if connected?(socket), do: safe_recent(name), else: []

    entries =
      Enum.map(recent, fn line -> %{id: System.unique_integer([:positive]), line: line} end)

    {:ok,
     socket
     |> assign(
       name: name,
       page_title: "Logs · #{name}",
       line_count: length(entries),
       eof: nil,
       tailer_failed: tailer == :error
     )
     |> stream(:log_lines, entries)}
  end

  @impl true
  def handle_info({:log_line, line}, socket) do
    id = System.unique_integer([:positive])

    {:noreply,
     socket
     |> assign(line_count: socket.assigns.line_count + 1)
     |> stream_insert(:log_lines, %{id: id, line: line}, limit: -@max_buffered_lines)}
  end

  def handle_info({:log_eof, code}, socket) do
    {:noreply, assign(socket, eof: code)}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp safe_start_tailer(name) do
    case Atlas.Control.LogTailer.Supervisor.start_tail(name) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      _other -> :error
    end
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  defp safe_recent(name) do
    Atlas.Control.LogTailer.recent(name)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-2xl font-bold">Logs: {@name}</h1>
      <.link navigate={~p"/admin/services"} class="btn btn-ghost btn-sm">← back to Services</.link>
    </div>

    <div :if={@tailer_failed} class="alert alert-warning mb-3 max-w-2xl" data-role="logs-stream-error">
      <span>
        Could not start the log stream — the control plane may be unreachable.
        Check the docker socket configuration (DOCKER_GID) and reload.
      </span>
    </div>

    <div
      id="log-viewer"
      phx-update="stream"
      phx-hook="LogStream"
      class="bg-neutral text-neutral-content p-4 rounded font-mono text-xs overflow-y-auto h-[70vh]"
    >
      <p :for={{dom_id, entry} <- @streams.log_lines} id={dom_id}>{entry.line}</p>
    </div>

    <p
      :if={@line_count == 0 and is_nil(@eof) and not @tailer_failed}
      class="mt-2 text-sm text-base-content/60"
      data-role="logs-waiting"
    >
      Waiting for log output…
    </p>
    <p :if={@eof} class="mt-2 text-sm text-base-content/60" data-role="logs-eof">
      Log stream ended (exit {@eof}).
    </p>
    """
  end
end
