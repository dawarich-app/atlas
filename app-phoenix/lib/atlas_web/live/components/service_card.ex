defmodule AtlasWeb.ServiceCard do
  use AtlasWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="card bg-base-200 shadow">
      <div class="card-body">
        <div class="flex justify-between items-center">
          <h3 class="card-title">{@service.name}</h3>
          <span class={status_badge(@service.status)}>{status_label(@service.status)}</span>
        </div>

        <p :if={@service.phase} class="text-sm opacity-80">Phase: {@service.phase}</p>

        <progress
          :if={@service.progress}
          class="progress progress-primary"
          value={@service.progress * 100}
          max="100"
        >
        </progress>

        <details class="collapse collapse-arrow border border-base-300 bg-base-100">
          <summary class="collapse-title text-sm">Last log</summary>
          <pre class="collapse-content text-xs whitespace-pre-wrap">{@service.last_log || "—"}</pre>
        </details>

        <div class="card-actions">
          <button
            phx-click="toggle_service"
            phx-value-name={@service.name}
            phx-value-enabled={to_string(@service.enabled)}
            class="btn btn-sm"
          >
            {if @service.enabled, do: "Disable", else: "Enable"}
          </button>
          <button
            phx-click="update_now"
            phx-value-name={@service.name}
            class="btn btn-sm btn-primary"
          >
            Update now
          </button>
          <.link
            navigate={~p"/admin/services/#{@service.name}/logs"}
            class="btn btn-sm btn-ghost"
          >
            Logs
          </.link>
        </div>

        <form phx-submit="schedule" class="form-control mt-2">
          <input type="hidden" name="name" value={@service.name} />
          <label class="label"><span class="label-text">Auto-update cron</span></label>
          <input
            type="text"
            name="cron"
            value={@service.update_schedule_cron || ""}
            placeholder="0 3 * * *"
            class="input input-sm input-bordered"
          />
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

  defp status_badge(:ready), do: "badge badge-success"
  defp status_badge(:error), do: "badge badge-error"
  defp status_badge(:unhealthy), do: "badge badge-warning"
  defp status_badge(_), do: "badge badge-info"

  defp status_label(nil), do: "unknown"
  defp status_label(s) when is_atom(s), do: Atom.to_string(s)
  defp status_label(s), do: to_string(s)
end
