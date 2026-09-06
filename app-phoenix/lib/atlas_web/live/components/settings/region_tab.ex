defmodule AtlasWeb.Settings.RegionTab do
  @moduledoc """
  Region tab of the settings drawer — pick a region and review what applying it will change.
  """

  use Phoenix.Component

  import AtlasWeb.IconHelpers

  alias Atlas.Control.RegionCatalog
  alias AtlasWeb.Components.ApplyTimelineComponent

  attr :regions, :list, required: true
  attr :tree_index, :map, required: true
  attr :by_name, :map, required: true
  attr :selection, :any, required: true
  attr :region_query, :string, required: true
  attr :expanded, :any, required: true
  attr :quick_picks, :list, required: true
  attr :timeline, :any, default: nil
  attr :myself, :any, required: true

  def region_tab(assigns) do
    q = String.trim(to_string(assigns.region_query))
    roots = Map.get(assigns.tree_index, nil, [])
    {visible, open} = tree_visibility(assigns.regions, assigns.by_name, assigns.expanded, q)

    assigns =
      assigns
      |> assign(:q, q)
      |> assign(:roots, roots)
      |> assign(:visible, visible)
      |> assign(:open, open)

    ~H"""
    <div>
      <ApplyTimelineComponent.timeline timeline={@timeline} />

      <.selected_tray selection={@selection} by_name={@by_name} />

      <div :if={@regions == []} class="text-sm text-base-content/60">No region presets found.</div>

      <div :if={@regions != []}>
        <form phx-change="region_search" phx-target={@myself} class="relative">
          <input
            type="text"
            name="q"
            aria-label="Search regions"
            value={@region_query}
            phx-debounce="150"
            placeholder="Search regions…"
            class="w-full rounded-2xl border-2 border-base-content/10 bg-base-300/40 px-4 py-3 pr-11 text-[15px] text-base-content outline-none transition focus:border-base-content"
          />
          <span class="pointer-events-none absolute right-3.5 top-1/2 -translate-y-1/2 text-base-content/55">
            {icon("search", class: "w-[18px] h-[18px]")}
          </span>
        </form>

        <div :if={@q == ""} class="mt-[18px]">
          <div class="mb-[11px] font-mono text-[11px] uppercase tracking-[0.2em] text-base-content/55">
            Quick picks
          </div>
          <div class="grid grid-cols-2 gap-2.5">
            <.quick_pick
              :for={r <- @quick_picks}
              region={r}
              selected={region_selected?(r, @selection)}
            />
          </div>
        </div>

        <div class="mb-1.5 mt-[22px] font-mono text-[11px] uppercase tracking-[0.2em] text-base-content/55">
          All regions
        </div>

        <div
          :if={@q != "" and MapSet.size(@visible) == 0}
          class="text-sm text-base-content/60"
        >
          No regions match "{@q}".
        </div>

        <div :if={@roots != []}>
          <.region_node
            :for={node <- @roots}
            :if={@q == "" or MapSet.member?(@visible, node.name)}
            node={node}
            depth={0}
            tree_index={@tree_index}
            selection={@selection}
            visible={@visible}
            open={@open}
            searching={@q != ""}
            myself={@myself}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :selection, :any, required: true
  attr :by_name, :map, required: true

  defp selected_tray(assigns) do
    active = assigns.selection |> List.wrap() |> Enum.filter(& &1.active)
    assigns = assign(assigns, :active, active)

    ~H"""
    <div :if={@active != []} class="mb-4" data-role="selected-tray">
      <div class="mb-2 flex items-center font-mono text-[11px] uppercase tracking-[0.2em] text-base-content/55">
        Selected regions ({length(@active)})
        <button
          type="button"
          phx-click="clear_regions"
          phx-disable-with="Clearing…"
          class="ml-auto normal-case tracking-normal text-[12px] font-semibold text-error/80"
        >
          clear all
        </button>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          :for={row <- @active}
          type="button"
          phx-click="toggle_region"
          phx-value-name={row.region_name}
          phx-disable-with="Removing…"
          data-selected-chip={row.region_name}
          class="btn btn-sm btn-primary gap-1"
          aria-label={"Remove " <> row.region_name}
        >
          {selection_label(@by_name, row.region_name)} <span aria-hidden="true">×</span>
        </button>
      </div>
    </div>
    """
  end

  defp selection_label(by_name, name) do
    case Map.get(by_name, name) do
      %{label: label} when is_binary(label) and label != "" -> label
      _ -> name
    end
  end

  attr :region, :map, required: true
  attr :selected, :boolean, required: true

  defp quick_pick(assigns) do
    ~H"""
    <label id={"region-quick-choice-" <> @region.name} class="region-choice flex cursor-pointer items-center gap-2.5 rounded-xl border border-base-content/15 px-3 py-3 text-left transition has-[:checked]:border-primary has-[:checked]:bg-primary/10">
      <input id={"region-quick-" <> @region.name} type="checkbox" checked={@selected} phx-click="toggle_region" phx-value-name={@region.name}
        aria-label={"Select " <> @region.label} class="checkbox checkbox-sm checkbox-primary shrink-0" />
      <span class="flex-1 min-w-0 text-sm font-medium">{@region.label}</span>
      <span class="region-saving text-xs text-primary" role="status">Saving…</span>
      <span class="flex-none font-mono text-[10.5px] text-base-content/55">{RegionCatalog.size_label(@region)}</span>
    </label>
    """
  end

  attr :node, :map, required: true
  attr :depth, :integer, required: true
  attr :tree_index, :map, required: true
  attr :selection, :any, required: true
  attr :visible, :any, required: true
  attr :open, :any, required: true
  attr :searching, :boolean, required: true
  attr :myself, :any, required: true

  defp region_node(assigns) do
    children = Map.get(assigns.tree_index, assigns.node.name, [])

    assigns =
      assigns
      |> assign(:children, children)
      |> assign(:node_open, MapSet.member?(assigns.open, assigns.node.name))
      |> assign(:selected, region_selected?(assigns.node, assigns.selection))

    ~H"""
    <div id={"region-node-" <> @node.name} data-node={@node.name}>
      <div class={["mx-1.5 my-0.5 flex items-center gap-2 rounded-xl py-1 pr-3", indent_class(@depth)]}>
        <button :if={@children != []} type="button" phx-click="toggle_node" phx-value-name={@node.name}
          phx-target={@myself} aria-label={"Expand " <> @node.label} aria-expanded={to_string(@node_open)}
          class="grid place-items-center p-1 text-base-content/55">
          <span class={["inline-block transition-transform duration-200", @node_open && "rotate-90"]}>
            {icon("chevron-down", class: "w-3.5 h-3.5 -rotate-90")}
          </span>
        </button>
        <span :if={@children == []} class="w-[18px] flex-none"></span>
        <label class="region-choice flex min-w-0 flex-1 cursor-pointer items-center gap-2.5 rounded-xl p-2 has-[:checked]:bg-primary/10">
          <input id={"region-select-" <> @node.name} type="checkbox" checked={@selected} phx-click="toggle_region" phx-value-name={@node.name}
            aria-label={"Select " <> @node.label} class="checkbox checkbox-sm checkbox-primary shrink-0" />
          <span class="min-w-0 flex-1 text-[15px]">{@node.label}</span>
          <span class="region-saving text-xs text-primary" role="status">Saving…</span>
          <span class="shrink-0 font-mono text-xs text-base-content/55">{RegionCatalog.size_label(@node)}</span>
        </label>
      </div>
      <div :if={@node_open and @children != []}>
        <.region_node
          :for={child <- @children}
          :if={not @searching or MapSet.member?(@visible, child.name)}
          node={child}
          depth={@depth + 1}
          tree_index={@tree_index}
          selection={@selection}
          visible={@visible}
          open={@open}
          searching={@searching}
          myself={@myself}
        />
      </div>
    </div>
    """
  end

  defp indent_class(0), do: "pl-1"
  defp indent_class(1), do: "pl-7"
  defp indent_class(2), do: "pl-12"
  defp indent_class(_), do: "pl-16"

  def tree_visibility(_regions, _by_name, expanded, ""), do: {MapSet.new(), expanded}

  def tree_visibility(regions, by_name, _expanded, q) do
    needle = String.downcase(q)

    matches =
      Enum.filter(regions, fn r ->
        haystack =
          [r.label, r.name | r.iso || []]
          |> Enum.join(" ")
          |> String.downcase()

        String.contains?(haystack, needle)
      end)

    ancestors =
      Enum.reduce(matches, MapSet.new(), fn match, acc ->
        collect_ancestors(match.parent, by_name, acc)
      end)

    match_names = MapSet.new(matches, & &1.name)
    visible = MapSet.union(match_names, ancestors)

    open =
      Enum.reduce(matches, ancestors, fn match, acc ->
        if match_has_children?(regions, match.name) do
          MapSet.put(acc, match.name)
        else
          acc
        end
      end)

    {visible, open}
  end

  defp collect_ancestors(nil, _by_name, acc), do: acc

  defp collect_ancestors(name, by_name, acc) do
    if MapSet.member?(acc, name) do
      acc
    else
      acc = MapSet.put(acc, name)

      case Map.get(by_name, name) do
        %{parent: parent} -> collect_ancestors(parent, by_name, acc)
        _ -> acc
      end
    end
  end

  defp match_has_children?(regions, name) do
    Enum.any?(regions, &(&1.parent == name))
  end

  def region_selected?(region, selection) when is_list(selection) do
    Enum.any?(selection, &(&1.region_name == region.name and &1.active))
  end

  def region_selected?(_, _), do: false
end
