defmodule AtlasWeb.Admin.ServicesLive do
  use AtlasWeb, :live_view

  alias Atlas.Control.{Safe, Service, ServiceSchedule, ServiceState, Seeder, Jobs}
  alias Atlas.Repo

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Enum.each(Seeder.known_services(), fn s ->
        Phoenix.PubSub.subscribe(Atlas.PubSub, "control:service:#{s.name}")
      end)
    end

    {:ok, assign(socket, services: load_services(), page_title: "Services")}
  end

  @impl true
  def handle_event("toggle_service", %{"name" => name, "enabled" => enabled_str}, socket) do
    if enabled_str == "true" do
      Safe.call(fn -> ServiceState.disable(name) end)
    else
      Safe.call(fn -> ServiceState.enable(name) end)
    end

    {:noreply, assign(socket, services: load_services())}
  end

  @impl true
  def handle_event("toggle_auto", %{"name" => name}, socket) do
    new_enabled =
      case Safe.snapshot(name) do
        %{auto_update_enabled?: cur} -> !cur
        _ -> true
      end

    Safe.call(fn -> ServiceState.set_auto_update(name, new_enabled) end)
    {:noreply, assign(socket, services: load_services())}
  end

  @impl true
  def handle_event("update_now", %{"name" => name}, socket) do
    %{name: name}
    |> Jobs.UpdateService.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Update enqueued for #{name}")}
  end

  @impl true
  def handle_event("schedule", %{"name" => name, "cron" => cron}, socket) do
    trimmed = String.trim(cron)

    cond do
      trimmed == "" ->
        ServiceSchedule.persist!(name, nil)

        {:noreply,
         socket
         |> put_flash(:info, "Schedule cleared for #{name}")
         |> assign(services: load_services())}

      ServiceSchedule.valid?(trimmed) ->
        ServiceSchedule.persist!(name, trimmed)

        {:noreply,
         socket
         |> put_flash(:info, "Schedule updated for #{name}")
         |> assign(services: load_services())}

      true ->
        {:noreply, put_flash(socket, :error, "Invalid cron expression")}
    end
  end

  @impl true
  def handle_info({:service_update, snapshot}, socket) do
    services =
      Enum.map(socket.assigns.services, fn s ->
        if s.name == snapshot.name, do: merge_snapshot(s, snapshot), else: s
      end)

    {:noreply, assign(socket, services: services)}
  end

  def handle_info({:persist_cron, name, cron}, socket) do
    ServiceSchedule.persist!(name, cron)

    flash_msg =
      if is_nil(cron),
        do: "Schedule cleared for #{name}",
        else: "Schedule updated for #{name}"

    {:noreply,
     socket
     |> put_flash(:info, flash_msg)
     |> assign(services: load_services())}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp preflight_failures do
    Atlas.Control.Preflight.results() |> Atlas.Control.Preflight.failures()
  rescue
    _ -> []
  end

  defp load_services do
    Enum.map(Seeder.known_services(), fn known ->
      row =
        Repo.get_by(Service, name: known.name) ||
          %Service{name: known.name, profile: known.profile}

      snap = Safe.snapshot(known.name) || %{}
      merge_snapshot(Map.from_struct(row), snap)
    end)
  end

  @snapshot_passthrough_keys [:name, :profile, :status, :phase, :progress, :last_log, :last_error]

  defp merge_snapshot(base, snap) do
    passthrough =
      snap
      |> Map.take(@snapshot_passthrough_keys)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    base
    |> Map.merge(passthrough)
    |> Map.put(:enabled, value_of(snap[:enabled?], base[:enabled]))
    |> Map.put(
      :auto_update_enabled,
      value_of(snap[:auto_update_enabled?], base[:auto_update_enabled])
    )
  end

  defp value_of(nil, fallback), do: fallback
  defp value_of(v, _), do: v

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :preflight_failures, preflight_failures())

    ~H"""
    <h1 class="text-2xl font-bold mb-4">Services</h1>

    <div
      :if={@preflight_failures != []}
      class="alert alert-error mb-4 max-w-3xl items-start"
      data-role="preflight-banner"
    >
      <div>
        <h3 class="font-semibold">Control plane degraded</h3>
        <div :for={f <- @preflight_failures} class="mt-2 text-sm">
          <span :if={f.detail} class="font-mono text-xs">{f.detail}</span>
          <p :if={f.remedy} class="text-xs mt-0.5">{f.remedy}</p>
        </div>
      </div>
    </div>

    <div class="space-y-4">
      <.live_component
        :for={service <- @services}
        module={AtlasWeb.ServiceCard}
        id={"service-#{service.name}"}
        service={service}
      />
    </div>
    """
  end
end
