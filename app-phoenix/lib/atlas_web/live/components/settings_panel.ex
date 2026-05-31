defmodule AtlasWeb.SettingsPanel do
  use AtlasWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:active_regions, fn -> [] end)
     |> assign_new(:basemap_source, fn -> basemap_source(assigns[:tiles_url] || "") end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="card bg-base-200 mb-4">
      <div class="card-body p-4">
        <div class="font-mono text-[10px] uppercase tracking-[0.14em] text-primary/80">
          Control plane
        </div>
        <h2 class="text-base font-semibold leading-tight">Settings</h2>

        <%= render_tiles_section(assigns) %>
        <%= render_regions_section(assigns) %>
        <%= render_basemap_section(assigns) %>
        <%= render_services_section(assigns) %>
      </div>
    </div>
    """
  end

  defp render_tiles_section(assigns) do
    ~H"""
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
    """
  end

  defp render_regions_section(assigns) do
    ~H"""
    <section class="mt-4 border-t border-base-300 pt-3" data-section="regions">
      <h3 class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 mb-2">
        Region
      </h3>
      <%= if @active_regions == [] do %>
        <div class="text-xs text-base-content/60">No regions selected.</div>
      <% else %>
        <ul class="text-xs space-y-0.5">
          <li :for={name <- @active_regions} class="flex justify-between">
            <span class="font-mono">{name}</span>
            <span class="text-success">active</span>
          </li>
        </ul>
      <% end %>
      <.link navigate={~p"/admin/regions"} class="text-xs link link-hover mt-2 inline-block">
        Manage regions →
      </.link>
    </section>
    """
  end

  defp render_basemap_section(assigns) do
    ~H"""
    <section class="mt-4 border-t border-base-300 pt-3" data-section="basemap">
      <h3 class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 mb-2">
        Basemap
      </h3>
      <div class="bg-base-200/40 rounded-md p-2 text-xs space-y-1">
        <div class="flex justify-between">
          <span class="text-base-content/60">Source</span>
          <span class="font-mono">{basemap_source_label(@basemap_source)}</span>
        </div>
        <div class="flex justify-between gap-2">
          <span class="text-base-content/60">URL</span>
          <span class="font-mono text-[10px] truncate text-right" title={@tiles_url}>
            {truncate(@tiles_url, 36)}
          </span>
        </div>
      </div>
    </section>
    """
  end

  defp render_services_section(assigns) do
    ~H"""
    <%= if @service_status != %{} do %>
      <section class="mt-4 border-t border-base-300 pt-3" data-section="services">
        <h3 class="font-mono text-[10px] uppercase tracking-[0.14em] text-base-content/55 mb-2">
          Services
        </h3>
        <ul class="text-xs space-y-0.5">
          <li :for={{name, snap} <- @service_status} class="flex justify-between items-center">
            <span class="font-mono">{name}</span>
            <span class="flex items-center gap-1">
              <span class={status_class(snap)}>{status_label(snap)}</span>
              <button
                type="button"
                phx-click="toggle_service_quick"
                phx-target={@myself}
                phx-value-name={name}
                phx-value-enabled={to_string(enabled?(snap))}
                class="btn btn-ghost btn-xs"
                title={if enabled?(snap), do: "Disable", else: "Enable"}
              >
                {if enabled?(snap), do: "off", else: "on"}
              </button>
            </span>
          </li>
        </ul>
      </section>
    <% end %>
    """
  end

  @impl true
  def handle_event("toggle_service_quick", %{"name" => name, "enabled" => enabled}, socket) do
    cond do
      enabled == "true" ->
        safe_call(fn -> Atlas.Control.ServiceState.disable(name) end)

      true ->
        safe_call(fn -> Atlas.Control.ServiceState.enable(name) end)
    end

    {:noreply, socket}
  end

  defp safe_call(fun) do
    fun.()
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  defp basemap_source(url) when is_binary(url) do
    cond do
      url == "" -> :unset
      String.starts_with?(url, "http://atlas-control") -> :sidecar
      String.contains?(url, "atlas-control:") -> :sidecar
      String.starts_with?(url, "pmtiles://") -> :sidecar
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") -> :external
      true -> :external
    end
  end

  defp basemap_source(_), do: :unset

  defp basemap_source_label(:sidecar), do: "sidecar"
  defp basemap_source_label(:external), do: "external"
  defp basemap_source_label(_), do: "unset"

  defp truncate(s, n) when is_binary(s) and byte_size(s) > n,
    do: String.slice(s, 0, n) <> "…"

  defp truncate(s, _), do: s || ""

  defp enabled?(%{enabled?: v}) when is_boolean(v), do: v
  defp enabled?(%{enabled: v}) when is_boolean(v), do: v
  defp enabled?(_), do: false

  defp status_label(nil), do: "—"
  defp status_label(%{status: status}) when is_atom(status), do: Atom.to_string(status)
  defp status_label(%{status: status}) when is_binary(status), do: status
  defp status_label(_), do: "—"

  defp status_class(%{status: :ready}), do: "text-success"
  defp status_class(%{status: :error}), do: "text-error"
  defp status_class(%{status: :starting}), do: "text-info"
  defp status_class(_), do: "text-base-content/50"
end
