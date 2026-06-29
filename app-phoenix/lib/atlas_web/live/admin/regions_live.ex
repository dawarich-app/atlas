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

    index = RegionCatalog.tree_index()

    {:ok,
     assign(socket,
       available: RegionCatalog.all(),
       tree_index: index,
       roots: Map.get(index, nil, []),
       selected: load_selected(),
       query: "",
       results: [],
       expanded: MapSet.new(),
       page_title: "Regions"
     )}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, assign(socket, query: q, results: RegionCatalog.search(q))}
  end

  @impl true
  def handle_event("expand", %{"name" => name}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded, name) do
        MapSet.delete(socket.assigns.expanded, name)
      else
        MapSet.put(socket.assigns.expanded, name)
      end

    {:noreply, assign(socket, expanded: expanded)}
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

  attr :region, :map, required: true
  attr :index, :map, required: true
  attr :expanded, :any, required: true
  attr :selected, :list, required: true

  def tree_node(assigns) do
    assigns = assign(assigns, :children, Map.get(assigns.index, assigns.region.name, []))
    assigns = assign(assigns, :open, MapSet.member?(assigns.expanded, assigns.region.name))

    ~H"""
    <li data-node={@region.name}>
      <div class="flex items-center gap-2">
        <button
          :if={@children != []}
          type="button"
          phx-click="expand"
          phx-value-name={@region.name}
          class="btn btn-xs btn-ghost"
        >
          {if @open, do: "▾", else: "▸"}
        </button>
        <button
          type="button"
          phx-click="toggle"
          phx-value-name={@region.name}
          class={["btn btn-xs", if(@region.name in @selected, do: "btn-primary", else: "btn-ghost")]}
        >
          {@region.label}
          <span class="opacity-60 ml-1">{RegionCatalog.size_label(@region)}</span>
        </button>
      </div>
      <ul :if={@open} class="ml-4">
        <.tree_node
          :for={c <- @children}
          region={c}
          index={@index}
          expanded={@expanded}
          selected={@selected}
        />
      </ul>
    </li>
    """
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

      <div :if={@selected != []} class="flex flex-wrap gap-2 mb-3">
        <AtlasWeb.RegionChip.selected_chip
          :for={name <- @selected}
          id={"sel-#{name}"}
          region={RegionCatalog.find(name) || %RegionCatalog{name: name, label: name, pbf_urls: []}}
        />
      </div>

      <form phx-change="search" phx-submit="search" class="mb-3">
        <input
          type="text"
          name="q"
          value={@query}
          phx-debounce="200"
          placeholder="Search countries, regions, cities…"
          class="input input-bordered w-full"
        />
      </form>

      <%= if @query != "" do %>
        <div class="flex flex-wrap gap-2 mb-4">
          <span :for={r <- @results} data-region={r.name}>
            <AtlasWeb.RegionChip.region_chip
              id={"result-#{r.name}"}
              region={r}
              selected={r.name in @selected}
            />
          </span>
        </div>
      <% else %>
        <ul class="menu menu-sm mb-4">
          <.tree_node
            :for={r <- @roots}
            region={r}
            index={@tree_index}
            expanded={@expanded}
            selected={@selected}
          />
        </ul>
      <% end %>

      <div class="flex gap-2">
        <button phx-click="save" class="btn btn-primary">Save</button>
        <.link navigate={~p"/admin/apply"} class="btn btn-ghost">Apply →</.link>
      </div>
    <% end %>
    """
  end
end
