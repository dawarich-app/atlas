defmodule AtlasWeb.Settings.PendingSummary do
  use Phoenix.Component

  alias Atlas.Control.{ApplyProjection, RegionCatalog}

  attr :enable, :list, required: true
  attr :disable, :list, required: true
  attr :region_names, :list, required: true
  attr :pending_services, :map, required: true

  def pending_summary(assigns) do
    region_structs =
      assigns.region_names
      |> Enum.map(&safe_find/1)
      |> Enum.reject(&is_nil/1)

    assigns =
      assigns
      |> assign(:region_labels, Enum.map(region_structs, & &1.label))
      |> assign(:projection, build_projection(region_structs, assigns.pending_services))

    ~H"""
    <div class="mb-3 rounded-2xl border border-primary/25 bg-primary/[0.07] px-3.5 py-3">
      <div class="mb-2 font-mono text-[10.5px] font-bold uppercase tracking-[0.14em] text-primary">
        Pending changes
      </div>

      <div :if={@enable != []} class="mb-1.5 flex flex-wrap items-center gap-1.5">
        <span class="font-mono text-[11px] uppercase tracking-[0.06em] text-base-content/55">
          enable
        </span>
        <span
          :for={name <- @enable}
          class="rounded-md bg-primary/15 px-1.5 py-0.5 font-mono text-[12px] font-semibold text-primary"
        >
          {name}
        </span>
      </div>

      <div :if={@disable != []} class="mb-1.5 flex flex-wrap items-center gap-1.5">
        <span class="font-mono text-[11px] uppercase tracking-[0.06em] text-base-content/55">
          disable
        </span>
        <span
          :for={name <- @disable}
          class="rounded-md bg-base-content/10 px-1.5 py-0.5 font-mono text-[12px] font-semibold text-base-content/70"
        >
          {name}
        </span>
      </div>

      <div :if={@region_labels != []} class="mb-1.5 flex flex-wrap items-center gap-1.5">
        <span class="font-mono text-[11px] uppercase tracking-[0.06em] text-base-content/55">
          region
        </span>
        <span
          :for={label <- @region_labels}
          class="rounded-md bg-base-content/10 px-1.5 py-0.5 font-mono text-[12px] font-semibold text-base-content/70"
        >
          {label}
        </span>
      </div>

      <div class="mt-1.5 border-t border-primary/15 pt-1.5 font-mono text-[12px] font-semibold text-primary">
        ≈ {@projection.total_disk_gb} GB · ~{@projection.first_boot_hours} h first boot
      </div>
    </div>
    """
  end

  defp build_projection(region_structs, pending_services) do
    intents =
      Enum.map(pending_services, fn {name, enabled} -> %{name: name, enabled: enabled} end)

    ApplyProjection.summary(region_structs, intents)
  rescue
    _ -> %{total_disk_gb: 0.0, first_boot_hours: 0.0}
  end

  defp safe_find(name) do
    RegionCatalog.find(name)
  rescue
    _ -> nil
  end
end
