defmodule AtlasWeb.Settings.CoverageModal do
  @moduledoc "Service-specific dataset coverage and provenance."
  use Phoenix.Component
  alias Phoenix.LiveView.JS

  attr :coverage, :map, required: true

  def coverage_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4 backdrop-blur-sm">
      <.focus_wrap id="service-coverage-dialog" role="dialog" aria-modal="true" aria-labelledby="coverage-title"
        phx-mounted={JS.focus_first(to: "#service-coverage-dialog")}
        phx-window-keydown={JS.push("close_service_coverage") |> JS.pop_focus()} phx-key="escape"
        phx-click-away={JS.push("close_service_coverage") |> JS.pop_focus()}
        class="flex max-h-[85vh] w-full max-w-2xl flex-col rounded-2xl border border-base-300 bg-base-100 shadow-2xl">
        <header class="flex items-start justify-between gap-4 border-b border-base-300 p-5">
          <div>
            <h2 id="coverage-title" class="text-xl font-bold">Regions and data · {@coverage.name}</h2>
            <p class="mt-1 text-sm text-base-content/65">Service-specific data, independent of your pending selection.</p>
          </div>
          <button type="button" aria-label="Close regions and data" class="btn btn-ghost btn-sm"
            phx-click={JS.push("close_service_coverage") |> JS.pop_focus()}>Close</button>
        </header>
        <div class="min-h-0 overflow-y-auto p-5" aria-live="polite" aria-busy={to_string(@coverage.loading)}>
          <p :if={@coverage.loading} class="flex items-center gap-2 text-sm">
            <span class="loading loading-spinner loading-sm"></span> Reading dataset metadata…
          </p>
          <div :if={@coverage.result}>
            <p class="mb-4 text-sm leading-relaxed text-base-content/70">{@coverage.result.note}</p>
            <p :if={@coverage.result.entries == []} class="rounded-xl bg-base-200 p-4 text-sm">No region list is available for this service.</p>
            <ul class="space-y-3">
              <li :for={entry <- @coverage.result.entries} class="rounded-xl border border-base-300 p-4">
                <p class="text-xs font-semibold text-base-content/65">{entry.kind}</p>
                <h3 class="mt-1 text-lg font-bold">{entry.label}</h3>
                <p class="mt-2 text-sm">{entry.evidence}</p>
                <p :if={entry[:date]} class="mt-1 text-sm text-base-content/65">Data timestamp: {entry.date}</p>
                <p :if={entry[:bounds] && entry.bounds != ""} class="mt-1 text-xs text-base-content/65">Bounds (west, south, east, north): {entry.bounds}</p>
                <p class="mt-2 break-all text-xs text-base-content/65">{entry.source}</p>
              </li>
            </ul>
          </div>
        </div>
      </.focus_wrap>
    </div>
    """
  end
end
