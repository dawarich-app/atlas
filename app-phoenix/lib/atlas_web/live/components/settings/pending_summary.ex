defmodule AtlasWeb.Settings.PendingSummary do
  @moduledoc """
  Summary of the not-yet-applied region change: what will be downloaded, converted and restarted.
  """

  use Phoenix.Component

  alias Atlas.Control.ApplyProjection

  attr :enable, :list, required: true
  attr :disable, :list, required: true
  attr :region_names, :list, required: true
  attr :pending_services, :map, required: true
  attr :region_changed, :boolean, default: false
  attr :previous_region_names, :list, default: []
  attr :by_name, :map, default: %{}

  def pending_summary(assigns) do
    region_structs =
      assigns.region_names
      |> Enum.map(&Map.get(assigns.by_name, &1))
      |> Enum.reject(&is_nil/1)

    assigns =
      assigns
      |> assign(
        :region_labels,
        Enum.map(assigns.region_names, &region_label(&1, assigns.by_name))
      )
      |> assign(
        :previous_labels,
        Enum.map_join(assigns.previous_region_names, ", ", &region_label(&1, assigns.by_name))
      )
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

      <p :if={@region_changed} class="mb-2 text-sm text-base-content/70">
        Regions: {if @previous_labels == "", do: "No selection", else: @previous_labels}
        → {if @region_labels == [], do: "No selection", else: Enum.join(@region_labels, ", ")}
      </p>
      <p :if={@region_changed and @region_labels == []} class="mb-2 text-sm text-base-content/70">
        Clears the selection. Existing datasets are kept.
      </p>
      <div :if={@region_labels != [] and @projection.total_disk_gb > 0} class="mt-1.5 border-t border-primary/15 pt-1.5 font-mono text-[12px] font-semibold text-primary">
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

  defp region_label(name, by_name) do
    case Map.get(by_name, name) do
      %{label: label} when is_binary(label) -> label
      _ -> name
    end
  end
end
