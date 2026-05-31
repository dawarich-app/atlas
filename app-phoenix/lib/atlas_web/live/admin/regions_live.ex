defmodule AtlasWeb.Admin.RegionsLive do
  use AtlasWeb, :live_view

  import Ecto.Query

  alias Atlas.Repo
  alias Atlas.Control.{RegionCatalog, RegionSelection}
  alias AtlasWeb.Admin.RegionsController

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Atlas.PubSub, "admin:regions")
    end

    {:ok,
     assign(socket,
       available: RegionCatalog.all(),
       selected: load_selected(),
       page_title: "Regions"
     )}
  end

  @impl true
  def handle_event("toggle", %{"name" => name}, socket) do
    new_selected =
      if name in socket.assigns.selected do
        List.delete(socket.assigns.selected, name)
      else
        socket.assigns.selected ++ [name]
      end

    {:noreply, assign(socket, selected: new_selected)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    names = socket.assigns.selected

    Repo.transaction(fn ->
      Repo.delete_all(RegionSelection)

      names
      |> Enum.with_index()
      |> Enum.each(fn {name, idx} ->
        %RegionSelection{}
        |> RegionSelection.changeset(%{
          region_name: name,
          position: idx,
          active: true
        })
        |> Repo.insert!()
      end)
    end)

    RegionsController.broadcast_selection_change(names)

    {:noreply,
     socket
     |> put_flash(:info, "Regions saved")
     |> assign(selected: load_selected())}
  end

  @impl true
  def handle_info({:regions_changed, _names}, socket) do
    # Reload from DB so this tab reflects changes made by another tab or
    # the JSON endpoint.
    {:noreply, assign(socket, selected: load_selected())}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp load_selected do
    RegionSelection
    |> where(active: true)
    |> order_by(:position)
    |> Repo.all()
    |> Enum.map(& &1.region_name)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1 class="text-2xl font-bold mb-4">Regions</h1>
    <%= if @available == [] do %>
      <p class="opacity-70">
        No region presets found in <code>priv/regions/</code>.
      </p>
    <% else %>
      <p class="opacity-70 mb-3">
        Select one or more region presets, then save. Use <.link navigate={~p"/admin/apply"} class="link">Apply</.link>
        to merge them into a working dataset.
      </p>
      <div class="flex flex-wrap gap-2 mb-4">
        <AtlasWeb.RegionChip.region_chip
          :for={r <- @available}
          id={"region-#{r.name}"}
          region={r}
          selected={r.name in @selected}
        />
      </div>
      <div class="flex gap-2">
        <button phx-click="save" class="btn btn-primary">Save</button>
        <.link navigate={~p"/admin/apply"} class="btn btn-ghost">Apply →</.link>
      </div>
    <% end %>
    """
  end
end
