defmodule AtlasWeb.Admin.ApplyLive do
  use AtlasWeb, :live_view

  import Ecto.Query

  alias Atlas.Repo
  alias Atlas.Control.{RegionApplier, RegionSelection}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       selected: load_selected(),
       apply_state: :idle,
       job_id: nil,
       error: nil,
       page_title: "Apply"
     )}
  end

  @impl true
  def handle_event("apply", _params, socket) do
    regions = Enum.map(socket.assigns.selected, & &1.region_name)

    case start_apply(regions) do
      {:ok, job_id} ->
        Phoenix.PubSub.subscribe(Atlas.PubSub, "control:apply:#{job_id}")
        {:noreply, assign(socket, apply_state: :running, job_id: job_id, error: nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(apply_state: :error, error: inspect(reason))
         |> put_flash(:error, "Failed to start apply: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:apply_start, job_id, _regions}, socket) do
    if job_id == socket.assigns.job_id do
      {:noreply, assign(socket, apply_state: :running)}
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
    RegionApplier.apply(regions)
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
      <button
        phx-click="apply"
        disabled={@apply_state == :running}
        class="btn btn-primary"
      >
        {apply_button_label(@apply_state)}
      </button>
      <%= if @error do %>
        <p class="text-error mt-2 text-sm">{@error}</p>
      <% end %>
    <% end %>
    """
  end

  defp apply_button_label(:running), do: "Applying…"
  defp apply_button_label(:done), do: "Apply again"
  defp apply_button_label(_), do: "Apply"
end
