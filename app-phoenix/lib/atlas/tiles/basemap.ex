defmodule Atlas.Tiles.Basemap do
  @moduledoc """
  Resolve a basemap preset id and either set its URL directly (no
  download), or kick off a download via `TilesDownloader` and report
  the resulting state machine back to the caller.

  Used by `MapLive` and any other surface that needs the
  "click a preset, apply it" flow.

  Returns one of:

    * `{:set_style, url}` — preset is a hosted style, persisted; caller
      should `push_event("map:set_style", %{url: url})`
    * `{:downloaded, local_url, dest}` — preset was downloaded; caller
      should set tiles_url + push set_style + flash success
    * `{:download_failed, reason}` — download attempt errored
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
      {:ok, _job_id, dest} ->
        local_url = "file://" <> dest
        Settings.set("tiles_url", local_url)
        {:downloaded, local_url, dest}

      {:error, reason} ->
        {:download_failed, reason}
    end
  catch
    :exit, _ -> :downloader_unavailable
  end
end
