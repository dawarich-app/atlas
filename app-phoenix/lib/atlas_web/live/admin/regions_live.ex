defmodule AtlasWeb.Admin.RegionsLive do
  use AtlasWeb, :live_view

  import Ecto.Query

  alias Atlas.Repo
  alias Atlas.Control.{RegionCatalog, RegionSelection}

  @impl true
  def mount(_params, _session, socket) do
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
    Repo.transaction(fn ->
      Repo.delete_all(RegionSelection)

      socket.assigns.selected
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

    {:noreply,
     socket
     |> put_flash(:info, "Regions saved")
     |> assign(selected: load_selected())}
  end

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
        <.live_component
          :for={r <- @available}
          module={AtlasWeb.RegionChip}
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
