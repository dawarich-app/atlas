defmodule AtlasWeb.Settings.Atoms do
  use Phoenix.Component

  import AtlasWeb.IconHelpers

  attr :class, :string, default: ""
  slot :inner_block, required: true

  def eyebrow(assigns) do
    ~H"""
    <div class={[
      "font-mono text-[11px] uppercase tracking-[0.2em] text-primary/70",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :count, :integer, required: true
  attr :avg, :integer, required: true

  def install_banner(assigns) do
    ~H"""
    <div class="mb-3.5 flex flex-wrap items-center gap-2.5 rounded-2xl border border-primary/20 bg-primary/[0.09] px-3.5 py-3">
      <.status_dot status={:starting} pulse={true} />
      <span class="text-sm font-bold text-primary">
        Installing {@count} service{if @count > 1, do: "s"}
      </span>
      <span class="ml-auto font-mono text-[13px] font-semibold text-primary">{@avg}%</span>
      <div class="w-full">
        <.progress_bar value={@avg * 1.0} tone="primary" />
      </div>
    </div>
    """
  end

  attr :enabled, :boolean, required: true

  def pending_badge(assigns) do
    ~H"""
    <span class="rounded-md bg-primary/15 px-1.5 py-0.5 font-mono text-[10px] font-semibold uppercase tracking-[0.05em] text-primary">
      pending {if @enabled, do: "on", else: "off"}
    </span>
    """
  end

  attr :value, :string, required: true
  attr :label, :string, required: true
  attr :flash, :boolean, default: false

  def mini_stat(assigns) do
    ~H"""
    <div class="text-right">
      <div class={[
        "font-mono text-[17px] font-semibold leading-none text-base-content whitespace-nowrap",
        @flash && "animate-pulse"
      ]}>
        {@value}
      </div>
      <div class="font-mono text-[9.5px] uppercase tracking-[0.14em] text-base-content/55 mt-1">
        {@label}
      </div>
    </div>
    """
  end

  attr :value, :float, required: true
  attr :tone, :string, default: "primary"

  def progress_bar(assigns) do
    ~H"""
    <div class="h-2 w-full overflow-hidden rounded-full bg-base-content/10">
      <div
        class={[
          "relative h-full overflow-hidden rounded-full transition-[width] duration-500",
          @tone == "warning" && "bg-warning",
          @tone == "primary" && "bg-primary"
        ]}
        style={"width: #{bar_width(@value)}%"}
      >
        <span :if={@value < 100} class="atlas-shimmer"></span>
      </div>
    </div>
    """
  end

  attr :status, :atom, default: nil
  attr :pulse, :boolean, default: false
  attr :glow, :boolean, default: false

  def status_dot(assigns) do
    ~H"""
    <span class="relative inline-block h-[9px] w-[9px] flex-none">
      <span :if={@pulse} class={["atlas-ping", dot_bg(@status)]}></span>
      <span class={[
        "absolute inset-0 rounded-full",
        dot_bg(@status),
        @glow && "shadow-[0_0_7px_currentColor]"
      ]}>
      </span>
    </span>
    """
  end

  attr :icon, :string, required: true
  attr :name, :string, required: true
  attr :count, :integer, default: nil
  attr :open, :boolean, default: false
  attr :click, :string, required: true
  attr :value, :string, required: true
  attr :target, :any, required: true
  slot :trailing

  def accordion_head(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@click}
      phx-value-cat={@value}
      phx-target={@target}
      class="flex w-full items-center gap-3 bg-transparent px-1 py-3 text-left"
    >
      <span class="text-base-content/70">{icon(@icon, class: "w-5 h-5")}</span>
      <span class="text-[15px] font-bold uppercase tracking-[0.03em] text-base-content">
        {@name}
      </span>
      <span :if={@count != nil} class="text-sm font-medium text-base-content/55">{@count}</span>
      {render_slot(@trailing)}
      <span class={["ml-auto text-base-content/55 transition-transform duration-200", @open && "rotate-180"]}>
        {icon("chevron-down", class: "w-4 h-4")}
      </span>
    </button>
    """
  end

  defp bar_width(v) when is_number(v), do: v |> max(2) |> min(100)
  defp bar_width(_), do: 2

  defp dot_bg(:ready), do: "bg-success text-success"

  defp dot_bg(status) when status in [:starting, :downloading, :building],
    do: "bg-warning text-warning"

  defp dot_bg(status) when status in [:error, :unhealthy], do: "bg-error text-error"
  defp dot_bg(_), do: "bg-base-content/30 text-base-content/30"
end
