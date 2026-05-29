defmodule AtlasWeb.SettingsPanel do
  use AtlasWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="card bg-base-200 mb-4">
      <div class="card-body p-4">
        <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-primary/80">
          Control plane
        </div>
        <h2 class="text-base font-semibold leading-tight">Settings</h2>

        <form phx-submit="save_settings" class="mt-2 flex flex-col gap-2">
          <label class="text-xs text-base-content/70">Tiles URL</label>
          <input
            type="text"
            name="tiles_url"
            value={@tiles_url}
            placeholder="https://… or pmtiles://…"
            class="input input-bordered input-sm w-full"
          />

          <label class="text-xs text-base-content/70 mt-1">Theme</label>
          <select name="theme" class="select select-bordered select-sm w-full">
            <option value="atlas-light" selected={@theme == "atlas-light"}>Light</option>
            <option value="atlas-dark" selected={@theme == "atlas-dark"}>Dark</option>
          </select>

          <button type="submit" class="btn btn-primary btn-sm mt-2">Save</button>
        </form>

        <%= if @service_status != %{} do %>
          <div class="mt-3 border-t border-base-300 pt-2">
            <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 mb-1">
              Services
            </div>
            <ul class="text-xs space-y-0.5">
              <li :for={{name, snap} <- @service_status} class="flex justify-between">
                <span>{name}</span>
                <span class={status_class(snap)}>{status_label(snap)}</span>
              </li>
            </ul>
          </div>
        <% end %>
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
