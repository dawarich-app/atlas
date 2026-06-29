defmodule AtlasWeb.Settings.BasemapTab do
  use Phoenix.Component

  import AtlasWeb.IconHelpers

  alias Atlas.Maps.BasemapPresets

  attr :presets, :list, required: true
  attr :tiles_url, :string, default: nil
  attr :tiles_download, :any, default: nil
  attr :basemap_confirm, :any, default: nil
  attr :themes, :list, required: true
  attr :theme, :string, required: true

  def basemap_tab(assigns) do
    ~H"""
    <div>
      <div class="flex flex-col gap-2.5">
        <.preset_card
          :for={preset <- @presets}
          preset={preset}
          active={active?(preset, @tiles_url)}
          download_state={download_state(preset, @tiles_download)}
          confirm={confirm_for(preset, @basemap_confirm)}
        />
      </div>

      <form phx-submit="save_settings" class="mt-3.5 flex items-stretch gap-2">
        <div class="min-w-0 flex-1">
          <input
            type="text"
            name="tiles_url"
            value={@tiles_url}
            placeholder="Custom style or pmtiles URL…"
            class="w-full rounded-2xl border-2 border-base-content/10 bg-base-300/40 px-4 py-3 font-mono text-sm text-base-content outline-none transition focus:border-base-content"
          />
        </div>
        <input type="hidden" name="theme" value={@theme} />
        <button
          type="submit"
          class="rounded-2xl bg-primary px-5 font-semibold text-primary-content"
        >
          Use
        </button>
      </form>

      <button
        type="button"
        phx-click="use_env_tiles"
        class="block px-1 py-2.5 text-[13.5px] font-semibold text-base-content/55 transition hover:text-primary"
      >
        Use .env default
      </button>

      <form phx-change="update_theme" class="mt-2 flex items-center gap-3">
        <span class="flex-none font-mono text-[11px] uppercase tracking-[0.16em] text-base-content/55">
          Theme
        </span>
        <div class="relative flex-1">
          <select
            name="theme"
            class="w-full appearance-none rounded-2xl border border-base-content/10 bg-base-300/40 px-4 py-3 text-sm text-base-content outline-none"
          >
            <option :for={t <- @themes} value={t} selected={@theme == t}>{theme_label(t)}</option>
          </select>
          <span class="pointer-events-none absolute right-4 top-1/2 -translate-y-1/2 text-base-content/55">
            {icon("chevron-down", class: "w-4 h-4")}
          </span>
        </div>
      </form>
    </div>
    """
  end

  attr :preset, :map, required: true
  attr :active, :boolean, required: true
  attr :download_state, :any, required: true
  attr :confirm, :any, default: nil

  defp preset_card(assigns) do
    ~H"""
    <div class={[
      "rounded-2xl border p-3.5 transition",
      @active && "border-primary bg-primary/[0.06]",
      !@active && "border-base-content/15"
    ]}>
      <div class="flex items-center gap-3.5">
        <div class="flex h-11 w-11 flex-none flex-col overflow-hidden rounded-xl border border-base-content/10">
          <div class="flex-1 bg-base-100"></div>
          <div class="flex-1 bg-base-300"></div>
          <div class="flex-1 bg-primary/30"></div>
        </div>
        <div class="min-w-0 flex-1">
          <div class="text-[15.5px] font-bold">{@preset.label}</div>
          <div class="mt-0.5 truncate font-mono text-[11px] text-base-content/55">{@preset.note}</div>
        </div>
        <span
          :if={@active and @download_state == nil}
          class="flex-none font-mono text-[10px] uppercase tracking-[0.1em] text-primary"
        >
          in use
        </span>
        <button
          :if={!@active and (@download_state == nil or @download_state.status != :running)}
          type="button"
          phx-click={if @preset.download, do: "confirm_basemap", else: "use_basemap"}
          phx-value-id={@preset.id}
          class="flex-none rounded-xl bg-primary px-4 py-2 text-[13.5px] font-bold text-primary-content"
        >
          {if @preset.download, do: "Download", else: "Use"}
        </button>
      </div>

      <div
        :if={@confirm}
        class="mt-3.5 rounded-xl bg-warning/10 px-3.5 py-3"
        data-role="basemap-confirm"
      >
        <div class="text-[13.5px] font-semibold">
          Download {size_label(@confirm[:size_bytes])} to <code class="font-mono">data/tiles/</code>?
        </div>
        <div class="mt-2.5 flex gap-2">
          <button
            type="button"
            phx-click="use_basemap"
            phx-value-id={@preset.id}
            class="rounded-xl bg-primary px-4 py-2 text-[13px] font-bold text-primary-content"
          >
            Start download
          </button>
          <button
            type="button"
            phx-click="cancel_basemap_confirm"
            class="rounded-xl px-4 py-2 text-[13px] font-semibold text-base-content/60"
          >
            Cancel
          </button>
        </div>
      </div>

      <div :if={@download_state} class="mt-3.5">
        <AtlasWeb.Settings.Atoms.progress_bar
          value={(@download_state[:progress] || 0.0) * 100}
          tone="primary"
        />
        <div class="mt-2 flex justify-between font-mono text-[11.5px] text-base-content/55">
          <span class="font-semibold text-primary">
            {Float.round((@download_state[:progress] || 0.0) * 100, 0) |> trunc()}% {Phoenix.Naming.humanize(to_string(@download_state.status))}
          </span>
          <span :if={@download_state[:reason]} class="text-error">{@download_state.reason}</span>
        </div>
      </div>
    </div>
    """
  end

  defp active?(preset, tiles_url) when is_binary(tiles_url) and tiles_url != "" do
    case BasemapPresets.resolve(preset.id) do
      {:ok, %{url: url}} -> url == tiles_url
      _ -> false
    end
  end

  defp active?(_preset, _tiles_url), do: false

  defp download_state(%{download: true}, %{} = dl), do: dl
  defp download_state(_preset, _dl), do: nil

  defp confirm_for(%{id: id, download: true}, %{id: id} = confirm), do: confirm
  defp confirm_for(_preset, _confirm), do: nil

  defp size_label(bytes) when is_integer(bytes) and bytes >= 1_000_000_000_000,
    do: "~#{Float.round(bytes / 1_000_000_000_000, 1)} TB"

  defp size_label(bytes) when is_integer(bytes) and bytes >= 1_000_000_000,
    do: "~#{Float.round(bytes / 1_000_000_000, 1)} GB"

  defp size_label(bytes) when is_integer(bytes) and bytes >= 1_000_000,
    do: "~#{Float.round(bytes / 1_000_000, 1)} MB"

  defp size_label(bytes) when is_integer(bytes), do: "#{bytes} bytes"
  defp size_label(_), do: "this tile pack (size unknown)"

  defp theme_label(t) do
    t
    |> String.replace("-", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
