defmodule AtlasWeb.Admin.ServicesLive do
  use AtlasWeb, :live_view

  alias Atlas.Control.{Service, ServiceState, Seeder, Jobs}
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
      safe_call(fn -> ServiceState.disable(name) end)
    else
      safe_call(fn -> ServiceState.enable(name) end)
    end

    {:noreply, assign(socket, services: load_services())}
  end

  @impl true
  def handle_event("toggle_auto", %{"name" => name}, socket) do
    new_enabled =
      case safe_snapshot(name) do
        %{auto_update_enabled?: cur} -> !cur
        _ -> true
      end

    safe_call(fn -> ServiceState.set_auto_update(name, new_enabled) end)
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
        persist_cron!(name, nil)
        {:noreply,
         socket
         |> put_flash(:info, "Schedule cleared for #{name}")
         |> assign(services: load_services())}

      valid_cron?(trimmed) ->
        persist_cron!(name, trimmed)
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
    persist_cron!(name, cron)

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

  defp load_services do
    Enum.map(Seeder.known_services(), fn known ->
      row =
        Repo.get_by(Service, name: known.name) ||
          %Service{name: known.name, profile: known.profile}

      snap = safe_snapshot(known.name) || %{}
      merge_snapshot(Map.from_struct(row), snap)
    end)
  end

  defp merge_snapshot(base, snap) do
    base
    |> Map.put(:name, snap[:name] || base[:name])
    |> Map.put(:profile, snap[:profile] || base[:profile])
    |> Map.put(:status, snap[:status] || base[:status])
    |> Map.put(:phase, snap[:phase] || base[:phase])
    |> Map.put(:progress, snap[:progress] || base[:progress])
    |> Map.put(:last_log, snap[:last_log] || base[:last_log])
    |> Map.put(:enabled, value_of(snap[:enabled?], base[:enabled]))
    |> Map.put(
      :auto_update_enabled,
      value_of(snap[:auto_update_enabled?], base[:auto_update_enabled])
    )
    |> Map.put(:update_schedule_cron, base[:update_schedule_cron])
  end

  defp value_of(nil, fallback), do: fallback
  defp value_of(v, _), do: v

  defp safe_snapshot(name) do
    ServiceState.snapshot(name)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp safe_call(fun) do
    fun.()
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  defp persist_cron!(name, cron) do
    case Repo.get_by(Service, name: name) do
      nil -> :ok
      row -> row |> Service.changeset(%{update_schedule_cron: cron}) |> Repo.update!()
    end
  end

  defp valid_cron?(expr) do
    case Crontab.CronExpression.Parser.parse(expr) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1 class="text-2xl font-bold mb-4">Services</h1>
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
