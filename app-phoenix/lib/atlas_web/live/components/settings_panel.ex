defmodule AtlasWeb.SettingsPanel do
  use AtlasWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <header class="px-4 pt-4 pb-3 border-b border-base-200">
        <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-primary/80">
          Control plane
        </div>
        <h2 class="text-base font-semibold leading-tight mt-0.5 font-display">Settings</h2>
      </header>

      <div class="flex-1 min-h-0 overflow-y-auto px-4 py-3 flex flex-col gap-4">
        <section>
          <h3 class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 mb-2 flex items-center gap-2">
            {icon("map", class: "w-3 h-3")} Basemap
          </h3>
          <form phx-submit="save_settings" class="flex flex-col gap-2">
            <input
              type="text"
              name="tiles_url"
              value={@tiles_url}
              placeholder="https://… or pmtiles://…"
              class="input input-bordered input-sm w-full"
            />
            <div class="flex items-center gap-2">
              <label class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 flex-shrink-0">
                Theme
              </label>
              <select name="theme" class="select select-bordered select-xs flex-1">
                <option value="forest-patina" selected={@theme == "forest-patina"}>
                  Forest Patina (light)
                </option>
                <option value="bunker-brutalist" selected={@theme == "bunker-brutalist"}>
                  Bunker Brutalist (dark)
                </option>
                <option value="atlas-light" selected={@theme == "atlas-light"}>Light</option>
                <option value="atlas-dark" selected={@theme == "atlas-dark"}>Dark</option>
              </select>
            </div>
            <button type="submit" class="btn btn-primary btn-sm mt-1">Save</button>
          </form>
        </section>

        <section :if={@service_status != %{}}>
          <h3 class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 mb-2 flex items-center gap-2">
            {icon("server", class: "w-3 h-3")} Services
          </h3>
          <ul class="text-xs flex flex-col gap-1">
            <li :for={{name, snap} <- @service_status} class="flex justify-between">
              <span>{name}</span>
              <span class={status_class(snap)}>{status_label(snap)}</span>
            </li>
          </ul>
        </section>
      </div>
    </div>
    """
  end

  defp status_label(nil), do: "—"
  defp status_label(%{status: status}) when is_atom(status), do: Atom.to_string(status)
  defp status_label(%{status: status}) when is_binary(status), do: status
  defp status_label(_), do: "—"

  defp status_class(%{status: :ready}), do: "text-success"
  defp status_class(%{status: :error}), do: "text-error"
  defp status_class(%{status: :starting}), do: "text-info"
  defp status_class(_), do: "text-base-content/50"
end
