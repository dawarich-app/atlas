defmodule AtlasWeb.LogViewer do
  @moduledoc """
  State behind `AtlasWeb.Settings.LogsModal`, shared by every LiveView that
  renders it. Lives in the `:service_logs` assign; the LiveView forwards its
  `open_logs`/`close_logs` events and `{:log_line, _}`/`{:log_eof, _}`
  messages here.

  `"apply"` is the region pipeline, which runs in-process and has no compose
  service to tail, so its lines come from `Atlas.Control.ApplyLog`.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Atlas.Control.{ApplyLog, LogTailer, Safe}

  @max_lines 500

  def open(socket, name) do
    unsubscribe(socket)
    Phoenix.PubSub.subscribe(Atlas.PubSub, "logs:#{name}")
    {tailer, recent} = source(name)
    lines = recent |> List.wrap() |> Enum.reverse() |> Enum.take(@max_lines)
    assign(socket, :service_logs, %{name: name, lines: lines, eof: nil, tailer: tailer})
  end

  def close(socket) do
    unsubscribe(socket)
    assign(socket, :service_logs, nil)
  end

  def line(%{assigns: %{service_logs: %{} = logs}} = socket, line),
    do: assign(socket, :service_logs, %{logs | lines: Enum.take([line | logs.lines], @max_lines)})

  def line(socket, _line), do: socket

  def eof(%{assigns: %{service_logs: %{} = logs}} = socket, code),
    do: assign(socket, :service_logs, %{logs | eof: code})

  def eof(socket, _code), do: socket

  defp unsubscribe(%{assigns: %{service_logs: %{name: name}}}),
    do: Phoenix.PubSub.unsubscribe(Atlas.PubSub, "logs:#{name}")

  defp unsubscribe(_socket), do: :ok

  defp source("apply") do
    case Safe.call(&ApplyLog.recent/0) do
      :unavailable -> {:error, []}
      lines -> {:ok, lines}
    end
  end

  defp source(name) do
    tailer =
      case Safe.call(fn -> LogTailer.Supervisor.start_tail(name) end) do
        :unavailable -> :error
        _ -> :ok
      end

    # An already-running tailer (attached at boot) consumed the compose
    # history before this viewer subscribed — replay its buffer.
    {tailer, Safe.call(fn -> LogTailer.recent(name) end, [])}
  end
end
