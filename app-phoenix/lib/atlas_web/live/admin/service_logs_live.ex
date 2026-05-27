defmodule AtlasWeb.Admin.ServiceLogsLive do
  @moduledoc ~S"""
  Streaming log viewer for one service.

  Subscribes to `"logs:#{name}"` and starts (or reuses) an
  `Atlas.Control.LogTailer` for that service via the dynamic supervisor.
  Lines arrive as `{:log_line, binary}` and are appended to a LiveView
  stream capped at `@max_buffered_lines`.

  The `LogStream` JS hook auto-scrolls the container on each insert.
  """
  use AtlasWeb, :live_view

  @max_buffered_lines 500

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Atlas.PubSub, "logs:#{name}")
      _ = safe_start_tailer(name)
    end

    {:ok,
     socket
     |> assign(name: name, page_title: "Logs · #{name}")
     |> stream(:log_lines, [])}
  end

  @impl true
  def handle_info({:log_line, line}, socket) do
    id = System.unique_integer([:positive])

    {:noreply,
     stream_insert(socket, :log_lines, %{id: id, line: line}, limit: -@max_buffered_lines)}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp safe_start_tailer(name) do
    Atlas.Control.LogTailer.Supervisor.start_tail(name)
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-2xl font-bold">Logs: {@name}</h1>
      <.link navigate={~p"/admin/services"} class="btn btn-ghost btn-sm">← back to Services</.link>
    </div>
    <div
      id="log-viewer"
      phx-update="stream"
      phx-hook="LogStream"
      class="bg-neutral text-neutral-content p-4 rounded font-mono text-xs overflow-y-auto h-[70vh]"
    >
      <p :for={{dom_id, entry} <- @streams.log_lines} id={dom_id}>{entry.line}</p>
    </div>
    """
  end
end
