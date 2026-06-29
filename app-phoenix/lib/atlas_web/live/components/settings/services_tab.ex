defmodule AtlasWeb.Settings.ServicesTab do
  use Phoenix.Component

  import AtlasWeb.IconHelpers
  import AtlasWeb.Settings.Atoms

  alias Atlas.Control.ServiceFormatting, as: SF

  @categories [
    {"geocoding", "Geocoding", "search"},
    {"routing", "Routing", "route"},
    {"pois", "POIs", "map-pin"},
    {"transit", "Transit", "clock"},
    {"data-setup", "Data setup", "server"}
  ]

  attr :known_services, :list, required: true
  attr :service_status, :map, required: true
  attr :pending_services, :map, default: %{}
  attr :open_cats, :any, required: true
  attr :open_upd, :any, required: true
  attr :info_for, :string, default: nil
  attr :myself, :any, required: true

  def services_tab(assigns) do
    installing = installing_snapshots(assigns.service_status)

    assigns =
      assigns
      |> assign(:categories, @categories)
      |> assign(:installing, installing)
      |> assign(:install_avg, install_avg(installing))

    ~H"""
    <div>
      <.install_banner :if={@installing != []} count={length(@installing)} avg={@install_avg} />

      <.category
        :for={{profile, label, cat_icon} <- @categories}
        :if={services_in(@known_services, profile) != []}
        profile={profile}
        label={label}
        cat_icon={cat_icon}
        services={services_in(@known_services, profile)}
        service_status={@service_status}
        pending_services={@pending_services}
        open={MapSet.member?(@open_cats, profile)}
        open_upd={@open_upd}
        info_for={@info_for}
        myself={@myself}
      />
    </div>
    """
  end

  attr :profile, :string, required: true
  attr :label, :string, required: true
  attr :cat_icon, :string, required: true
  attr :services, :list, required: true
  attr :service_status, :map, required: true
  attr :pending_services, :map, default: %{}
  attr :open, :boolean, required: true
  attr :open_upd, :any, required: true
  attr :info_for, :string, default: nil
  attr :myself, :any, required: true

  defp category(assigns) do
    running = Enum.count(assigns.services, &SF.running?(assigns.service_status[&1.name]))
    assigns = assign(assigns, :running, running)

    ~H"""
    <div class="border-t border-base-content/[0.07]">
      <div class="flex items-center">
        <div class="flex-1">
          <.accordion_head
            icon={@cat_icon}
            name={@label}
            count={length(@services)}
            open={@open}
            click="toggle_cat"
            value={@profile}
            target={@myself}
          />
        </div>
        <span
          :if={!@open and @running > 0}
          class="mr-2 font-mono text-[10.5px] text-primary"
        >
          {@running} on
        </span>
      </div>

      <div :if={@open} class="flex flex-col gap-1.5 pb-2">
        <.service_row
          :for={svc <- @services}
          svc={svc}
          snapshot={@service_status[svc.name]}
          pending={Map.fetch(@pending_services, svc.name)}
          upd_open={MapSet.member?(@open_upd, svc.name)}
          info_open={@info_for == svc.name}
          myself={@myself}
        />
      </div>
    </div>
    """
  end

  attr :svc, :map, required: true
  attr :snapshot, :any, default: nil
  attr :pending, :any, default: :error
  attr :upd_open, :boolean, required: true
  attr :info_open, :boolean, required: true
  attr :myself, :any, required: true

  defp service_row(assigns) do
    snap = assigns.snapshot
    installing = SF.installing?(snap)
    running = SF.running?(snap)
    {pending?, desired} = pending_state(assigns.pending, SF.enabled?(snap))

    assigns =
      assigns
      |> assign(:installing, installing)
      |> assign(:running, running)
      |> assign(:status, snap && Map.get(snap, :status))
      |> assign(:enabled, desired)
      |> assign(:pending?, pending?)
      |> assign(:auto, match?(%{auto_update_enabled?: true}, snap))

    ~H"""
    <div class={[
      "rounded-2xl px-3.5 py-3 transition",
      @installing && "bg-warning/[0.07]",
      @running && "bg-primary/[0.05]",
      !@installing && !@running && "bg-base-200/50"
    ]}>
      <div class="flex items-center gap-2.5">
        <.status_dot status={@status} pulse={@installing} glow={@running} />
        <span class="font-mono text-[15px] font-semibold">{@svc.name}</span>
        <span class={["font-mono text-[11.5px] uppercase tracking-[0.05em]", status_text(@status)]}>
          {if @installing, do: "#{SF.progress_pct(@snapshot)}%", else: SF.status_label(@snapshot)}
        </span>
        <.pending_badge :if={@pending?} enabled={@enabled} />
        <div class="ml-auto flex items-center gap-1.5">
          <button
            type="button"
            phx-click="toggle_info"
            phx-value-name={@svc.name}
            phx-target={@myself}
            class={[
              "grid h-[30px] w-[30px] place-items-center rounded-lg transition",
              @info_open && "bg-primary/15 text-primary",
              !@info_open && "text-base-content/55"
            ]}
            aria-label={"About " <> @svc.name}
          >
            {icon("info", class: "w-4 h-4")}
          </button>
          <button
            type="button"
            phx-click="open_logs"
            phx-value-name={@svc.name}
            class="grid h-[30px] w-[30px] place-items-center rounded-lg text-base-content/55"
            aria-label={"View logs for " <> @svc.name}
            title="Logs"
          >
            {icon("scroll-text", class: "w-4 h-4")}
          </button>
          <input
            type="checkbox"
            class="toggle toggle-sm toggle-primary"
            phx-click="toggle_service"
            phx-value-name={@svc.name}
            checked={@enabled}
          />
        </div>
      </div>

      <div :if={@info_open} class="mt-2.5 text-[13px] leading-relaxed text-base-content/70">
        {info_blurb(@snapshot, @svc)}
      </div>

      <div :if={@installing} class="mt-3">
        <.progress_bar value={SF.progress_pct(@snapshot) * 1.0} tone="warning" />
        <div :if={SF.phase_label(@snapshot)} class="mt-1.5 font-mono text-[11.5px] font-semibold capitalize text-warning">
          {SF.phase_label(@snapshot)}
        </div>
      </div>

      <div :if={@running} class="mt-2 flex gap-3.5 font-mono text-[11.5px] text-base-content/55">
        <span>disk {SF.disk_label(@snapshot)}</span>
        <span>updated {updated_label(@snapshot)}</span>
      </div>

      <div class="mt-2.5 border-t border-base-content/[0.07] pt-2.5">
        <button
          type="button"
          phx-click="toggle_upd"
          phx-value-name={@svc.name}
          phx-target={@myself}
          class={[
            "flex w-full items-center gap-2 font-mono text-[10.5px] uppercase tracking-[0.16em]",
            @upd_open && "text-primary",
            !@upd_open && "text-base-content/55"
          ]}
        >
          {icon("refresh-cw", class: "w-3.5 h-3.5")} Updates
          <span class="normal-case tracking-normal text-base-content/45">
            {if @auto, do: "· auto", else: "· manual"}
          </span>
          <span class={["ml-auto inline-block transition-transform duration-200", @upd_open && "rotate-180"]}>
            {icon("chevron-down", class: "w-3.5 h-3.5")}
          </span>
        </button>

        <div :if={@upd_open} class="mt-3 flex flex-col gap-3">
          <label class="flex cursor-pointer items-center gap-2.5">
            <input
              type="checkbox"
              class="toggle toggle-xs toggle-primary"
              phx-click="toggle_auto"
              phx-value-name={@svc.name}
              checked={@auto}
            />
            <span class="text-[13.5px] font-medium">Auto-update on schedule</span>
          </label>

          <form phx-submit="save_schedule" class="flex items-center gap-2.5">
            <input type="hidden" name="name" value={@svc.name} />
            <span class="w-8 flex-none font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55">
              Cron
            </span>
            <input
              type="text"
              name="cron"
              placeholder="0 3 * * *"
              class="flex-1 rounded-xl border border-base-content/10 bg-base-300/40 px-3 py-2.5 font-mono text-[13px] text-base-content outline-none"
            />
            <button type="submit" class="font-semibold text-[13.5px] text-primary">Save</button>
          </form>

          <button
            type="button"
            phx-click="update_now"
            phx-value-name={@svc.name}
            class="flex items-center justify-center gap-2 rounded-xl border-[1.5px] border-primary py-3 text-[13.5px] font-bold text-primary"
          >
            {icon("refresh-cw", class: "w-[15px] h-[15px]")} Update now
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp pending_state({:ok, desired}, _current), do: {true, desired}
  defp pending_state(_, current), do: {false, current}

  defp services_in(services, profile) do
    services
    |> Enum.filter(&(&1.profile == profile))
    |> Enum.sort_by(& &1.name)
  end

  defp installing_snapshots(status_map) when is_map(status_map) do
    status_map
    |> Map.values()
    |> Enum.filter(&SF.installing?/1)
  end

  defp installing_snapshots(_), do: []

  defp install_avg([]), do: 0

  defp install_avg(snaps) do
    (Enum.reduce(snaps, 0, &(&2 + SF.progress_pct(&1))) / length(snaps)) |> round()
  end

  defp status_text(:ready), do: "text-primary"
  defp status_text(status) when status in [:starting, :downloading, :building], do: "text-warning"
  defp status_text(status) when status in [:error, :unhealthy], do: "text-error"
  defp status_text(_), do: "text-base-content/55"

  defp info_blurb(%{last_log: log}, _svc) when is_binary(log) and log != "", do: log
  defp info_blurb(_snap, svc), do: "#{svc.name} · profile #{svc.profile}"

  defp updated_label(%{last_seen_at: %DateTime{} = dt}),
    do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp updated_label(_), do: "—"
end
