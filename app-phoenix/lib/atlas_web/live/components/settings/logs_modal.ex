defmodule AtlasWeb.Settings.LogsModal do
  @moduledoc """
  Full-page streaming log viewer for one service.

  Rendered at the MapLive root (NOT inside the side panel) so the overlay
  covers the whole viewport. All events (`close_logs`) target the root
  LiveView — no component indirection, and no `stopPropagation` handlers
  that would swallow clicks before LiveView's delegated listener sees them.
  """

  use Phoenix.Component

  import AtlasWeb.IconHelpers
  import AtlasWeb.Settings.Atoms

  alias Atlas.Control.ServiceFormatting, as: SF

  attr :name, :string, required: true
  attr :snapshot, :any, default: nil
  attr :logs, :any, default: nil

  def logs_modal(assigns) do
    snap = assigns.snapshot
    logs = assigns.logs

    assigns =
      assigns
      |> assign(:status, snap && Map.get(snap, :status))
      |> assign(:last_error, snap && Map.get(snap, :last_error))
      |> assign(:installing, SF.installing?(snap))
      |> assign(:pct, SF.progress_pct(snap))
      |> assign(:lines, (logs && Enum.reverse(logs.lines)) || [])
      |> assign(:eof, logs && logs.eof)
      |> assign(:tailer_failed, (logs && logs.tailer == :error) == true)

    ~H"""
    <div
      class="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4 sm:p-8 backdrop-blur-[2px]"
      data-role="logs-modal"
    >
      <div
        phx-click-away="close_logs"
        phx-window-keydown="close_logs"
        phx-key="escape"
        class="flex max-h-full h-[80vh] w-full max-w-4xl flex-col overflow-hidden rounded-2xl border border-white/10 bg-[#181d18] shadow-2xl"
      >
        <div class="flex items-center gap-2.5 border-b border-white/10 px-4 py-3">
          <.status_dot status={@status} pulse={@installing} />
          <span class="font-mono text-[13px] font-semibold text-[#e9e6dc]">{@name}</span>
          <span class="font-mono text-[11px] uppercase tracking-[0.08em] text-[#9fd6ad]">
            {SF.status_label(@snapshot)}{if @installing, do: " · #{@pct}%"}
          </span>
          <span class="ml-auto font-mono text-[11px] text-[#7c8378]">logs</span>
          <button
            type="button"
            phx-click="close_logs"
            class="ml-1.5 rounded-lg p-1.5 text-[#9aa093] transition hover:bg-white/10 hover:text-[#e9e6dc]"
            aria-label="Close logs"
          >
            {icon("x", class: "w-4 h-4")}
          </button>
        </div>

        <div :if={@last_error} class="border-b border-white/10 px-4 py-2.5">
          <div class="flex gap-2.5 font-mono text-[12px] leading-[1.6] text-[#e69b86]">
            <span class="w-12 flex-none">ERROR</span>
            <span class="break-words">{@last_error}</span>
          </div>
        </div>

        <div
          id="settings-log-viewer"
          phx-hook="LogStream"
          class="min-h-0 flex-1 overflow-auto px-4 py-3 font-mono text-[12px] leading-[1.7]"
        >
          <p
            :if={@tailer_failed and @lines == []}
            class="text-[#e69b86]"
            data-role="logs-stream-error"
          >
            Could not start the log stream — the control plane may be unreachable.
          </p>
          <p
            :if={!@tailer_failed and @lines == [] and is_nil(@eof)}
            class="text-[#7c8378]"
            data-role="logs-waiting"
          >
            Waiting for log output…
          </p>
          <p :for={line <- @lines} class="break-words text-[#cdd0c5]">{line}</p>
          <p :if={@eof} class="mt-1 text-[#7c8378]" data-role="logs-eof">
            — log stream ended (exit {@eof}) —
          </p>
        </div>
      </div>
    </div>
    """
  end
end
