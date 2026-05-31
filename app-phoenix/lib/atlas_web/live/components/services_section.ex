defmodule AtlasWeb.ServicesSection do
  @moduledoc """
  Per-profile services list rendered inside the Settings panel.
  Includes the toggle, status badge, and the per-service auto-update
  details disclosure (cron + Update now).
  """

  use Phoenix.Component

  alias Atlas.Control.ServiceFormatting

  import AtlasWeb.IconHelpers

  @profiles [
    {"geocoding", "Geocoding"},
    {"routing", "Routing"},
    {"pois", "POIs"},
    {"transit", "Transit"},
    {"data-setup", "Data setup"}
  ]

  attr :known_services, :list, required: true
  attr :service_status, :map, required: true

  def services_section(assigns) do
    assigns = assign(assigns, :profiles, @profiles)

    ~H"""
    <section>
      <h3 class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 mb-2 flex items-center gap-2">
        {icon("server", class: "w-3 h-3")} Services
      </h3>
      <div class="flex flex-col">
        <%= for {profile, label} <- @profiles do %>
          <% list = services_in_profile(@known_services, profile) %>
          <%= if list != [] do %>
            <h4 class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/45 mt-3 first:mt-0 mb-1 pl-3">
              {label}
            </h4>
            <.service_row :for={svc <- list} svc={svc} snapshot={@service_status[svc.name]} />
          <% end %>
        <% end %>
      </div>
    </section>
    """
  end

  attr :svc, :map, required: true
  attr :snapshot, :any, default: nil

  defp service_row(assigns) do
    ~H"""
    <div class="group relative pl-3 pr-2 py-2 rounded-md hover:bg-base-200/40 transition-colors">
      <span class={"absolute left-0 top-0 bottom-0 w-1 rounded-l-md " <> ServiceFormatting.status_bar_class(@snapshot)}></span>

      <div class="flex items-center gap-2">
        <span class="font-mono text-sm flex-1 min-w-0 truncate flex items-center gap-1.5">
          {@svc.name}
          <button
            type="button"
            class="text-base-content/40 hover:text-base-content/80 cursor-pointer inline-flex focus:outline-none focus:text-base-content/80 shrink-0"
            aria-label={"About " <> @svc.name}
          >
            {icon("info", class: "w-3.5 h-3.5")}
          </button>
          <button
            type="button"
            class="text-base-content/40 hover:text-base-content/80 cursor-pointer inline-flex focus:outline-none focus:text-base-content/80 shrink-0"
            aria-label={"View logs for " <> @svc.name}
            title="Logs"
          >
            {icon("scroll-text", class: "w-3.5 h-3.5")}
          </button>
        </span>
        <span class={"badge badge-sm " <> ServiceFormatting.badge_class(@snapshot)}>
          {ServiceFormatting.status_label(@snapshot)}
        </span>
        <span class="text-xs text-base-content/30 tabular-nums w-16 text-right">—</span>
        <label class="cursor-pointer shrink-0 flex flex-col items-end gap-0.5">
          <input
            type="checkbox"
            class="toggle toggle-sm toggle-primary"
            phx-click="toggle_service"
            phx-value-name={@svc.name}
            checked={ServiceFormatting.enabled?(@snapshot)}
          />
        </label>
      </div>

      <details class="mt-2 border-t border-base-200 pt-2">
        <summary class="cursor-pointer select-none flex items-center justify-between gap-2 list-none text-xs">
          <span class="flex items-center gap-1.5 text-base-content/70">
            {icon("refresh-cw", class: "w-3 h-3")}
            <span class="font-mono uppercase tracking-[0.14em] text-[10px]">Updates</span>
          </span>
          <span class="text-[10px] text-base-content/50 tabular-nums">—</span>
        </summary>

        <div class="mt-2 pl-1 grid grid-cols-1 gap-2 text-xs">
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              class="toggle toggle-xs toggle-primary"
              phx-click="toggle_auto"
              phx-value-name={@svc.name}
            />
            <span class="text-[11px]">Auto-update</span>
          </label>

          <form phx-submit="save_schedule" class="flex items-center gap-2">
            <input type="hidden" name="name" value={@svc.name} />
            <span class="font-mono uppercase tracking-[0.14em] text-[10px] text-base-content/40 shrink-0">
              Cron
            </span>
            <input
              type="text"
              name="cron"
              placeholder="0 3 * * *"
              class="input input-bordered input-xs flex-1 font-mono text-[11px]"
            />
            <button type="submit" class="btn btn-xs btn-ghost">Save</button>
          </form>

          <button
            type="button"
            phx-click="update_now"
            phx-value-name={@svc.name}
            class="btn btn-xs btn-outline btn-primary w-full"
          >
            {icon("refresh-cw", class: "w-3 h-3")} <span>Update now</span>
          </button>
        </div>
      </details>
    </div>
    """
  end

  defp services_in_profile(services, profile) do
    services
    |> Enum.filter(&(&1.profile == profile))
    |> Enum.sort_by(& &1.name)
  end
end
