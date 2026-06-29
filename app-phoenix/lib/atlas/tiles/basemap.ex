defmodule Atlas.Tiles.Basemap do
  @moduledoc """
  Resolve a basemap preset id and either set its URL directly (no
  download), or kick off an asynchronous download via `TilesDownloader`.

  Used by `MapLive` and any other surface that needs the
  "click a preset, apply it" flow.

  Returns one of:

    * `{:set_style, url}` — preset is a hosted style, persisted; caller
      should `push_event("map:set_style", %{url: url})`
    * `{:download_started, job_id, dest}` — download accepted; progress
      arrives on `TilesDownloader.topic()`, and the downloader persists the
      served URL itself on completion
    * `{:download_failed, reason}` — download could not start
    * `:downloader_unavailable` — `TilesDownloader` process not running
    * `:unknown` — no matching preset id
  """

  alias Atlas.Control.TilesDownloader
  alias Atlas.Maps.BasemapPresets
  alias Atlas.Settings

  def apply(id) do
    case BasemapPresets.resolve(id) do
      {:ok, %{url: url, download: false}} when is_binary(url) ->
        Settings.set("tiles_url", url)
        {:set_style, url}

      {:ok, %{url: url, download: true}} when is_binary(url) ->
        download(url)

      _ ->
        :unknown
    end
  end

  defp download(url) do
    case TilesDownloader.download(url) do
      {:ok, job_id, dest} ->
        {:download_started, job_id, dest}

      {:error, :busy} ->
        {:download_failed, "a tile-pack download is already running"}

      {:error, reason} ->
        {:download_failed, reason}
    end
  catch
    :exit, _ -> :downloader_unavailable
  end
end
