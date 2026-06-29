defmodule AtlasWeb.Settings.RegionTab do
  use Phoenix.Component

  import AtlasWeb.IconHelpers

  alias Atlas.Control.RegionCatalog

  attr :regions, :list, required: true
  attr :tree_index, :map, required: true
  attr :by_name, :map, required: true
  attr :selection, :any, required: true
  attr :region_query, :string, required: true
  attr :expanded, :any, required: true
  attr :quick_picks, :list, required: true
  attr :apply_status, :any, default: nil
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
      <.apply_card :if={@apply_status} status={@apply_status} />

      <.selected_tray selection={@selection} by_name={@by_name} />

      <div :if={@regions == []} class="text-sm text-base-content/60">No region presets found.</div>

      <div :if={@regions != []}>
        <form phx-change="region_search" phx-target={@myself} class="relative">
          <input
            type="text"
            name="q"
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

  attr :status, :map, required: true

  defp apply_card(assigns) do
    error = Map.get(assigns.status, :error)

    assigns =
      assigns
      |> assign(:error, error)
      |> assign(:phase, Map.get(assigns.status, :phase))
      |> assign(:region, Map.get(assigns.status, :region))
      |> assign(:progress, Map.get(assigns.status, :progress))
      |> assign(:regions, Map.get(assigns.status, :regions, []))

    ~H"""
    <div
      class={[
        "mb-4 rounded-2xl px-3.5 py-3",
        @error && "bg-error/10",
        !@error && "bg-warning/10"
      ]}
      data-role="apply-card"
    >
      <div :if={!@error}>
        <div class="flex items-center gap-2 font-mono text-[12px] font-semibold text-warning">
          <span class="loading loading-spinner loading-xs"></span>
          Applying {Enum.join(@regions, ", ")}
        </div>
        <div class="mt-1.5 font-mono text-[11.5px] capitalize text-base-content/70">
          {phase_text(@phase)}<%= if @region do %> · {@region}<% end %>
          <%= if is_number(@progress) do %>
            · {round(@progress * 100)}%
          <% end %>
        </div>
        <progress
          :if={is_number(@progress)}
          class="progress progress-warning mt-2 w-full"
          value={round(@progress * 100)}
          max="100"
        >
        </progress>
      </div>

      <div :if={@error}>
        <div class="font-mono text-[12px] font-semibold text-error">
          Region apply failed ({phase_text(@phase)})
        </div>
        <div class="mt-1.5 break-words font-mono text-[11.5px] text-base-content/70">
          {@error}
        </div>
      </div>
    </div>
    """
  end

  defp phase_text(:downloading), do: "downloading"
  defp phase_text(:merging), do: "merging"
  defp phase_text(:converting), do: "converting for overpass"
  defp phase_text(:staging), do: "staging transit inputs"
  defp phase_text(:restarting), do: "restarting services"
  defp phase_text(_), do: "working"

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
    <button
      type="button"
      phx-click="toggle_region"
      phx-value-name={@region.name}
      class={[
        "flex items-center gap-2.5 rounded-xl border px-3 py-3 text-left transition",
        @selected && "border-primary bg-primary/10",
        !@selected && "border-base-content/15 bg-transparent"
      ]}
    >
      <span class={[
        "grid h-[18px] w-[18px] flex-none place-items-center rounded-full border-2",
        @selected && "border-primary bg-primary text-primary-content",
        !@selected && "border-base-content/30"
      ]}>
        <span :if={@selected}>{icon("check", class: "w-[11px] h-[11px]")}</span>
      </span>
      <span class={[
        "flex-1 min-w-0 truncate text-sm",
        @selected && "font-bold text-primary",
        !@selected && "font-medium text-base-content"
      ]}>
        {@region.label}
      </span>
      <span class="flex-none font-mono text-[10.5px] text-base-content/55">
        {RegionCatalog.size_label(@region)}
      </span>
    </button>
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
    <div data-node={@node.name}>
      <div
        phx-click="toggle_region"
        phx-value-name={@node.name}
        class={[
          "mx-1.5 my-0.5 flex cursor-pointer items-center gap-2.5 rounded-xl py-2.5 pr-3 transition",
          @selected && "bg-primary/10",
          indent_class(@depth)
        ]}
      >
        <button
          :if={@children != []}
          type="button"
          phx-click="toggle_node"
          phx-value-name={@node.name}
          phx-target={@myself}
          class="grid place-items-center p-0.5 text-base-content/55"
        >
          <span class={["inline-block transition-transform duration-200", @node_open && "rotate-90"]}>
            {icon("chevron-down", class: "w-3.5 h-3.5 -rotate-90")}
          </span>
        </button>
        <span :if={@children == []} class="w-[18px] flex-none"></span>
        <span class={[
          "grid h-[19px] w-[19px] flex-none place-items-center rounded-full border-2 transition",
          @selected && "border-primary bg-primary text-primary-content",
          !@selected && "border-base-content/30"
        ]}>
          <span :if={@selected}>{icon("check", class: "w-[11px] h-[11px]")}</span>
        </span>
        <span class={[
          "flex-1 min-w-0 truncate text-[15px]",
          @selected && "font-bold text-primary",
          !@selected && "font-medium text-base-content"
        ]}>
          {@node.label}
        </span>
        <span class="flex-none whitespace-nowrap font-mono text-xs text-base-content/55">
          {RegionCatalog.size_label(@node)}
        </span>
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
