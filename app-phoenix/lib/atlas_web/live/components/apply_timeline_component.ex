defmodule AtlasWeb.Components.ApplyTimelineComponent do
  @moduledoc """
  Renders one `Atlas.Control.ApplyTimeline.Timeline` — the single markup
  shared by the settings drawer's region tab and the `/admin/apply` page, so
  both surfaces show identical apply progress detail.

  Tolerates `timeline: nil` (the server broadcasts `{:timeline, nil}` on boot
  and after a crash).
  """

  use AtlasWeb, :html

  alias Atlas.Control.ApplyTimeline
  alias Atlas.Control.RegionCatalog

  attr :timeline, :any, required: true

  def timeline(assigns) do
    ~H"""
    <div :if={@timeline} data-role="apply-timeline">
      <div class="flex items-center gap-2 font-mono text-[12px] font-semibold">
        <span :if={@timeline.status == :running} class="loading loading-spinner loading-xs"></span>
        {Enum.join(@timeline.regions, ", ")}
        <span class="text-base-content/55">
          · step {@timeline.current_step} of {length(@timeline.stages)}
        </span>
        <button
          :if={@timeline.status != :running}
          type="button"
          phx-click="dismiss_timeline"
          class="ml-auto text-base-content/45 transition hover:text-base-content"
          title="Dismiss"
          aria-label="Dismiss apply timeline"
        >
          ✕
        </button>
      </div>

      <ol class="mt-2 space-y-1.5">
        <li :for={stage <- @timeline.stages} class="font-mono text-[11.5px]">
          <div class="flex items-baseline gap-2">
            <span class="w-3 text-base-content/55">
              <span
                :if={stage.state == :running}
                class="loading loading-spinner loading-xs align-middle"
              >
              </span>
              <span :if={stage.state != :running}>{state_glyph(stage.state)}</span>
            </span>
            <span class={stage_class(stage.state)}>{stage.label}</span>
            <span :if={stage.detail} class="text-base-content/55">{stage.detail}</span>
            <span :if={ApplyTimeline.percentage(stage.measure)} class="text-base-content/70">
              {ApplyTimeline.percentage(stage.measure)}%
            </span>
            <span :if={stage.error} class="text-error">{stage.error}</span>
          </div>

          <ul :if={stage.items != []} class="ml-5 mt-1 space-y-0.5">
            <li :for={item <- stage.items} class="text-base-content/70">
              <span class="w-3 text-base-content/55">{state_glyph(item.state)}</span>
              {item.label}
              <span :if={ApplyTimeline.percentage(item.measure)}>
                · {ApplyTimeline.percentage(item.measure)}%
              </span>
              <span :if={is_nil(ApplyTimeline.percentage(item.measure)) and item.measure}>
                · {RegionCatalog.format_bytes(item.measure.current)}
              </span>
              <div :if={item.source} class="ml-5 break-all text-[10.5px] text-base-content/45">
                {item.source}
              </div>
            </li>
          </ul>
        </li>
      </ol>
    </div>
    """
  end

  defp state_glyph(:done), do: "✓"
  defp state_glyph(:running), do: "▸"
  defp state_glyph(:error), do: "✗"
  defp state_glyph(:skipped), do: "⊘"
  defp state_glyph(_state), do: "○"

  defp stage_class(:running), do: "font-semibold"
  defp stage_class(:error), do: "text-error"
  defp stage_class(:skipped), do: "text-base-content/40"
  defp stage_class(_state), do: ""
end
