defmodule AtlasWeb.Admin.ApplyLive do
  use AtlasWeb, :live_view

  import Ecto.Query

  alias Atlas.Repo
  alias Atlas.Control.{RegionApplier, RegionCatalog, RegionSelection, Safe}
  import AtlasWeb.AdminErrorComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Atlas.PubSub, RegionApplier.topic())
    end

    status = Safe.call(fn -> RegionApplier.status() end, nil)

    {:ok,
     socket
     |> assign(
       selected: load_selected(),
       projection: nil,
       missing_region: nil,
       page_title: "Apply"
     )
     |> assign_status(status)}
  end

  defp assign_status(socket, nil) do
    assign(socket, apply_state: :idle, job: nil, error: nil)
  end

  defp assign_status(socket, %{error: error} = status) when not is_nil(error) do
    assign(socket, apply_state: :error, job: status, error: error)
  end

  defp assign_status(socket, status) do
    assign(socket, apply_state: :applying, job: status, error: nil)
  end

  @impl true
  def handle_event("project", _params, socket) do
    region_names = Enum.map(socket.assigns.selected, & &1.region_name)

    case missing_region(region_names) do
      nil ->
        projection = RegionApplier.project(region_names, [])

        {:noreply,
         assign(socket, apply_state: :projected, projection: projection, missing_region: nil)}

      name ->
        {:noreply, assign(socket, apply_state: :error, missing_region: name)}
    end
  end

  @impl true
  def handle_event("cancel_projection", _params, socket) do
    {:noreply, assign(socket, apply_state: :idle, projection: nil)}
  end

  @impl true
  def handle_event("confirm_apply", _params, socket) do
    if socket.assigns.apply_state != :projected do
      {:noreply, put_flash(socket, :error, "Project regions before confirming.")}
    else
      regions = Enum.map(socket.assigns.selected, & &1.region_name)

      case start_apply(regions) do
        {:ok, job_id} ->
          job = %{job_id: job_id, regions: regions, phase: :downloading, progress: nil}
          {:noreply, assign(socket, apply_state: :applying, job: job, error: nil)}

        error_term ->
          message = format_error(unwrap_error(error_term))

          {:noreply,
           socket
           |> assign(apply_state: :error, error: message)
           |> put_flash(:error, "Failed to start apply: #{message}")}
      end
    end
  end

  @impl true
  def handle_info({:apply_start, %{job_id: job_id, regions: regions}}, socket) do
    job = %{job_id: job_id, regions: regions, phase: :downloading, progress: nil}
    {:noreply, assign(socket, apply_state: :applying, job: job, error: nil)}
  end

  def handle_info({:apply_progress, %{job_id: job_id} = progress}, socket) do
    if match?(%{job_id: ^job_id}, socket.assigns.job) do
      {:noreply, assign(socket, job: Map.merge(socket.assigns.job, progress))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:apply_done, %{job_id: job_id}}, socket) do
    if match?(%{job_id: ^job_id}, socket.assigns.job) do
      {:noreply, socket |> assign(apply_state: :done) |> put_flash(:info, "Apply complete")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:apply_error, %{job_id: job_id, reason: reason}}, socket) do
    if match?(%{job_id: ^job_id}, socket.assigns.job) do
      message = format_error(reason)

      {:noreply,
       socket
       |> assign(apply_state: :error, error: message)
       |> put_flash(:error, "Apply failed: #{message}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp start_apply(regions) do
    RegionApplier.start(regions)
  rescue
    e -> {:error, e}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp unwrap_error({:error, reason}), do: reason
  defp unwrap_error(other), do: other

  defp load_selected do
    RegionSelection
    |> where(active: true)
    |> order_by(:position)
    |> Repo.all()
  end

  defp missing_region(names) do
    Enum.find(names, fn name ->
      is_nil(RegionCatalog.find(name))
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1 class="text-2xl font-bold mb-4">Apply Regions</h1>
    <%= if @selected == [] do %>
      <p>
        No regions selected.
        <.link navigate={~p"/admin/regions"} class="link">Select some first</.link>.
      </p>
    <% else %>
      <ul class="menu bg-base-200 rounded-box mb-4 max-w-md">
        <li :for={r <- @selected}>
          <span>{r.region_name}</span>
        </li>
      </ul>

      <%= render_state(assigns) %>
    <% end %>
    """
  end

  defp render_state(%{apply_state: :idle} = assigns) do
    ~H"""
    <div class="flex gap-2">
      <button phx-click="project" class="btn btn-primary">Project</button>
    </div>
    <%= if @error do %>
      <p class="text-error mt-2 text-sm">{@error}</p>
    <% end %>
    """
  end

  defp render_state(%{apply_state: :projected, projection: projection} = assigns)
       when not is_nil(projection) do
    assigns = assign(assigns, :projection, projection)

    ~H"""
    <div class="card bg-base-200 mb-3 max-w-2xl">
      <div class="card-body">
        <h3 class="font-semibold">Projection</h3>
        <p class="text-sm">
          About <strong>{@projection.total_disk_gb} GB</strong>
          on disk, first-boot ETA <strong>{@projection.first_boot_hours} h</strong>.
        </p>

        <table class="table table-xs mt-2">
          <thead>
            <tr><th>Service</th><th class="text-right">Disk (GB)</th><th class="text-right">Hours</th></tr>
          </thead>
          <tbody>
            <tr :for={line <- @projection.lines}>
              <td class="font-mono">{line.name}</td>
              <td class="text-right tabular-nums">{line.disk_gb}</td>
              <td class="text-right tabular-nums">{line.hours}</td>
            </tr>
          </tbody>
        </table>

        <%= if @projection.service_intents != [] do %>
          <div class="mt-2 text-xs">
            <div class="font-mono uppercase tracking-wide text-base-content/55 mb-1">
              Service intents
            </div>
            <ul>
              <li :for={intent <- @projection.service_intents}>
                {intent.name}: {if intent.enabled, do: "enable", else: "disable"}
              </li>
            </ul>
          </div>
        <% end %>
      </div>
    </div>

    <div class="flex gap-2">
      <button phx-click="confirm_apply" class="btn btn-primary">Confirm Apply</button>
      <button phx-click="cancel_projection" class="btn btn-ghost">Cancel</button>
    </div>
    """
  end

  defp render_state(%{apply_state: :applying} = assigns) do
    ~H"""
    <div class="card bg-base-200 mb-3 max-w-2xl">
      <div class="card-body">
        <h3 class="font-semibold flex items-center gap-2">
          <span class="loading loading-spinner loading-sm"></span> Applying…
        </h3>
        <%= if @job do %>
          <p class="text-sm font-mono">
            {phase_label(@job[:phase])}<%= if @job[:region] do %> · {@job[:region]}<% end %>
            <%= if is_number(@job[:progress]) do %>
              · {round(@job[:progress] * 100)}%
            <% end %>
          </p>
          <progress
            :if={is_number(@job[:progress])}
            class="progress progress-primary w-full"
            value={round(@job[:progress] * 100)}
            max="100"
          >
          </progress>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_state(%{apply_state: :done} = assigns) do
    ~H"""
    <div class="alert alert-success max-w-2xl mb-3">
      <div>
        <div class="font-semibold">Apply complete</div>
        <%= if @projection do %>
          <div class="text-xs">
            Downloaded ~{@projection.total_disk_gb} GB · first-boot ETA ~{@projection.first_boot_hours} h.
          </div>
        <% end %>
      </div>
    </div>
    <button phx-click="project" class="btn btn-primary">Apply again</button>
    """
  end

  defp render_state(%{apply_state: :error} = assigns) do
    ~H"""
    <%= if @missing_region do %>
      <.region_not_found name={@missing_region} available={available_region_names()} />
    <% end %>
    <button phx-click="project" class="btn btn-primary">Retry</button>
    <%= if @error do %>
      <p class="text-error mt-2 text-sm">{@error}</p>
    <% end %>
    """
  end

  defp phase_label(:downloading), do: "downloading"
  defp phase_label(:merging), do: "merging"
  defp phase_label(:converting), do: "converting for overpass"
  defp phase_label(:staging), do: "staging transit inputs"
  defp phase_label(:restarting), do: "restarting services"
  defp phase_label(_), do: "working"

  defp available_region_names do
    RegionCatalog.all() |> Enum.map(& &1.name)
  end
end
