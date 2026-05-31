defmodule AtlasWeb.Admin.ApplyLive do
  use AtlasWeb, :live_view

  import Ecto.Query

  alias Atlas.Repo
  alias Atlas.Control.{RegionApplier, RegionCatalog, RegionSelection}
  import AtlasWeb.AdminErrorComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       selected: load_selected(),
       apply_state: :idle,
       projection: nil,
       missing_region: nil,
       job_id: nil,
       error: nil,
       page_title: "Apply"
     )}
  end

  @impl true
  def handle_event("project", _params, socket) do
    region_names = Enum.map(socket.assigns.selected, & &1.region_name)

    case missing_region(region_names) do
      nil ->
        projection = RegionApplier.project(region_names, [])
        {:noreply, assign(socket, apply_state: :projected, projection: projection, missing_region: nil)}

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
          Phoenix.PubSub.subscribe(Atlas.PubSub, "control:apply:#{job_id}")
          {:noreply, assign(socket, apply_state: :applying, job_id: job_id, error: nil)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(apply_state: :error, error: inspect(reason))
           |> put_flash(:error, "Failed to start apply: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_info({:apply_start, job_id, _regions}, socket) do
    if job_id == socket.assigns.job_id do
      {:noreply, assign(socket, apply_state: :applying)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:apply_done, job_id, _regions}, socket) do
    if job_id == socket.assigns.job_id do
      {:noreply, socket |> assign(apply_state: :done) |> put_flash(:info, "Apply complete")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:apply_error, job_id, reason}, socket) do
    if job_id == socket.assigns.job_id do
      {:noreply,
       socket
       |> assign(apply_state: :error, error: inspect(reason))
       |> put_flash(:error, "Apply failed: #{inspect(reason)}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp start_apply(regions) do
    RegionApplier.start(regions)
  rescue
    e -> {:error, Exception.message(e)}
  catch
    :exit, reason -> {:error, reason}
  end

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
    <button disabled class="btn btn-primary">Applying…</button>
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

  defp available_region_names do
    RegionCatalog.all() |> Enum.map(& &1.name)
  end
end
