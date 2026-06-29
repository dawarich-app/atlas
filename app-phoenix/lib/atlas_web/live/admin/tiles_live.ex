defmodule AtlasWeb.Admin.TilesLive do
  use AtlasWeb, :live_view

  alias Atlas.Settings
  alias Atlas.Control.TilesDownloader
  alias AtlasWeb.Admin.TilesController

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Atlas.PubSub, TilesDownloader.topic())
    end

    tiles_url = Settings.tiles_url()

    {:ok,
     assign(socket,
       tiles_url: tiles_url,
       theme: Settings.tiles_theme(),
       tiles_source: TilesController.tiles_source(tiles_url),
       download_state: :idle,
       progress: 0.0,
       page_title: "Tiles"
     )}
  end

  @impl true
  def handle_event("save", %{"tiles_url" => url, "theme" => theme}, socket) do
    Settings.set("tiles_url", url)
    Settings.set("tiles_theme", theme)

    {:noreply,
     socket
     |> assign(tiles_url: url, theme: theme, tiles_source: TilesController.tiles_source(url))
     |> put_flash(:info, "Saved")}
  end

  def handle_event("reset_to_sidecar", _params, socket) do
    Settings.set("tiles_url", "")

    {:noreply,
     socket
     |> assign(tiles_url: "", tiles_source: :sidecar)
     |> put_flash(:info, "Tiles source reset to sidecar default")}
  end

  @impl true
  def handle_event("download", %{"url" => url}, socket) do
    trimmed = String.trim(url)

    if trimmed == "" do
      {:noreply, put_flash(socket, :error, "Provide a tile pack URL")}
    else
      case TilesDownloader.download(trimmed) do
        {:ok, _job_id, _dest} ->
          {:noreply, assign(socket, download_state: :running, progress: 0.0)}

        {:error, :busy} ->
          {:noreply, put_flash(socket, :error, "A tile-pack download is already running")}
      end
    end
  end

  @impl true
  def handle_info({:start, _job_id, _url, _dest}, socket) do
    {:noreply, assign(socket, download_state: :running, progress: 0.0)}
  end

  def handle_info({:progress, _job_id, p}, socket) do
    {:noreply, assign(socket, progress: p)}
  end

  def handle_info({:done, _job_id, _dest}, socket) do
    {:noreply,
     socket
     |> assign(download_state: :idle, progress: 1.0)
     |> put_flash(:info, "Download complete")}
  end

  def handle_info({:error, _job_id, reason}, socket) do
    {:noreply,
     socket
     |> assign(download_state: :error)
     |> put_flash(:error, "Download failed: #{reason}")}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <h1 class="text-2xl font-bold mb-4">Tiles</h1>
    <div class="mb-3 max-w-xl text-sm flex items-center gap-2">
      <span class="text-base-content/60">Source:</span>
      <span class={source_badge_class(@tiles_source)} data-tiles-source={Atom.to_string(@tiles_source)}>
        {source_label(@tiles_source)}
      </span>
      <%= if @tiles_source == :external do %>
        <button
          phx-click="reset_to_sidecar"
          class="btn btn-xs btn-ghost"
          title="Clear override; use sidecar default"
        >
          Reset to sidecar
        </button>
      <% end %>
    </div>

    <form phx-submit="save" class="form-control gap-2 max-w-xl">
      <label class="label"><span class="label-text">Tiles URL (PMTiles or style.json)</span></label>
      <input type="text" name="tiles_url" value={@tiles_url} class="input input-bordered" />
      <label class="label"><span class="label-text">Theme</span></label>
      <select name="theme" class="select select-bordered">
        <option value="atlas-light" selected={@theme == "atlas-light"}>Light</option>
        <option value="atlas-dark" selected={@theme == "atlas-dark"}>Dark</option>
      </select>
      <button class="btn btn-primary mt-2 w-fit">Save</button>
    </form>

    <form phx-submit="download" class="mt-6 form-control max-w-xl">
      <label class="label"><span class="label-text">Download new tile pack</span></label>
      <div class="join">
        <input
          type="text"
          name="url"
          placeholder="https://example.com/region.pmtiles"
          class="input input-bordered join-item flex-1"
        />
        <button class="btn btn-secondary join-item" disabled={@download_state == :running}>
          Download
        </button>
      </div>
      <%= if @download_state == :running do %>
        <progress class="progress mt-2" value={@progress * 100} max="100"></progress>
      <% end %>
    </form>
    """
  end

  defp source_label(:sidecar), do: "sidecar"
  defp source_label(:external), do: "external"
  defp source_label(_), do: "unset"

  defp source_badge_class(:sidecar), do: "badge badge-success"
  defp source_badge_class(:external), do: "badge badge-info"
  defp source_badge_class(_), do: "badge badge-ghost"
end
