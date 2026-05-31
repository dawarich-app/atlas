defmodule AtlasWeb.ServiceCard do
  use AtlasWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:cron_error, fn -> nil end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="card bg-base-200 shadow" data-service={@service.name}>
      <div class="card-body">
        <div class="flex justify-between items-center">
          <h3 class="card-title flex items-center gap-2">
            {@service.name}
            <%= if stale?(@service) do %>
              <span class="badge badge-xs badge-ghost" title={"Stale: last seen at #{@service[:last_seen_at]}"}>stale</span>
            <% end %>
          </h3>
          <span class={status_badge(@service.status)} data-status={status_label(@service.status)}>
            {status_label(@service.status)}
          </span>
        </div>

        <p :if={@service.phase} class="text-sm opacity-80">Phase: {@service.phase}</p>

        <progress
          :if={@service.progress}
          class="progress progress-primary"
          value={@service.progress * 100}
          max="100"
        >
        </progress>

        <%= if disk_human(@service[:disk_bytes]) do %>
          <p class="text-xs opacity-60">Disk: {disk_human(@service[:disk_bytes])}</p>
        <% end %>

        <%= if last_error(@service) do %>
          <div class="alert alert-error text-xs py-1" role="alert" data-error-line="true">
            <span class="truncate" title={last_error(@service)}>
              {truncate(last_error(@service), 140)}
            </span>
          </div>
        <% end %>

        <details class="collapse collapse-arrow border border-base-300 bg-base-100">
          <summary class="collapse-title text-sm">Last log</summary>
          <pre class="collapse-content text-xs whitespace-pre-wrap">{@service.last_log || "—"}</pre>
        </details>

        <div class="card-actions">
          <button
            phx-click="toggle_service"
            phx-value-name={@service.name}
            phx-value-enabled={to_string(@service.enabled)}
            phx-disable-with={if @service.enabled, do: "Disabling…", else: "Enabling…"}
            class="btn btn-sm"
            data-action="toggle"
          >
            {if @service.enabled, do: "Disable", else: "Enable"}
          </button>
          <button
            phx-click="update_now"
            phx-value-name={@service.name}
            phx-disable-with="Enqueuing…"
            disabled={update_running?(@service)}
            class="btn btn-sm btn-primary"
            data-action="update"
          >
            {if update_running?(@service), do: "Updating…", else: "Update now"}
          </button>
          <.link
            navigate={~p"/admin/services/#{@service.name}/logs"}
            class="btn btn-sm btn-ghost"
          >
            Logs
          </.link>
        </div>

        <form
          phx-submit="schedule"
          phx-target={@myself}
          class="form-control mt-2"
          data-form="schedule"
        >
          <input type="hidden" name="name" value={@service.name} />
          <label class="label"><span class="label-text">Auto-update cron</span></label>
          <input
            type="text"
            name="cron"
            value={@service.update_schedule_cron || ""}
            placeholder="0 3 * * *"
            class={["input input-sm input-bordered", @cron_error && "input-error"]}
          />
          <%= if @cron_error do %>
            <p class="text-error text-xs mt-1" data-error="cron">{@cron_error}</p>
          <% end %>
        </form>
        <label class="cursor-pointer label">
          <span class="label-text">Auto-update enabled</span>
          <input
            type="checkbox"
            phx-click="toggle_auto"
            phx-value-name={@service.name}
            checked={@service.auto_update_enabled || false}
            class="toggle"
          />
        </label>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("schedule", %{"name" => name, "cron" => cron}, socket) do
    trimmed = String.trim(cron)

    cond do
      trimmed == "" ->
        send(self(), {:persist_cron, name, nil})
        {:noreply, assign(socket, cron_error: nil)}

      valid_cron?(trimmed) ->
        send(self(), {:persist_cron, name, trimmed})
        {:noreply, assign(socket, cron_error: nil)}

      true ->
        {:noreply, assign(socket, cron_error: "Invalid cron expression (e.g. \"0 3 * * *\")")}
    end
  end

  defp valid_cron?(expr) do
    case Crontab.CronExpression.Parser.parse(expr) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp status_badge(:ready), do: "badge badge-success"
  defp status_badge(:error), do: "badge badge-error"
  defp status_badge(:unhealthy), do: "badge badge-warning"
  defp status_badge(:starting), do: "badge badge-info"
  defp status_badge(:downloading), do: "badge badge-info"
  defp status_badge(:building), do: "badge badge-info"
  defp status_badge(:stopped), do: "badge badge-ghost"
  defp status_badge(_), do: "badge badge-ghost"

  defp status_label(nil), do: "unknown"
  defp status_label(s) when is_atom(s), do: Atom.to_string(s)
  defp status_label(s), do: to_string(s)

  defp last_error(service) do
    err = service[:last_error]

    cond do
      is_binary(err) and String.trim(err) != "" ->
        err

      service[:status] in [:error, :unhealthy] and is_binary(service[:last_log]) and
          String.match?(service[:last_log], ~r/error|fail|denied/i) ->
        service[:last_log]

      true ->
        nil
    end
  end

  defp truncate(s, n) when is_binary(s) and byte_size(s) > n,
    do: String.slice(s, 0, n) <> "…"

  defp truncate(s, _), do: s || ""

  defp update_running?(service) do
    service[:last_update_status] == "running"
  end

  defp stale?(%{last_seen_at: %DateTime{} = ts}) do
    DateTime.diff(DateTime.utc_now(), ts, :second) > 30
  end

  defp stale?(_), do: false

  defp disk_human(n) when is_integer(n) and n > 0, do: human_size(n)
  defp disk_human(_), do: nil

  defp human_size(n) when n >= 1_073_741_824, do: "#{Float.round(n / 1_073_741_824, 1)} GB"
  defp human_size(n) when n >= 1_048_576, do: "#{Float.round(n / 1_048_576, 1)} MB"
  defp human_size(n) when n >= 1024, do: "#{Float.round(n / 1024, 1)} KB"
  defp human_size(n), do: "#{n} B"
end
