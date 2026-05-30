defmodule Atlas.Maps.BasemapPresets do
  @moduledoc """
  Built-in basemap presets that mirror the Rails Atlas `PRESETS` constant in
  `app/app/javascript/controllers/basemap_controller.js`.

  Each preset has:

    * `:id`       — stable identifier (used by `phx-value-id`)
    * `:label`    — human-readable name shown in the card title
    * `:note`     — short description shown under the title
    * `:url`      — static tiles URL, or `nil` if built dynamically
    * `:download` — `true` if the preset is large enough to require a local download
    * `:url_fn`   — optional 0-arity function that builds the URL at call time
                     (e.g. Protomaps daily planet build keyed by today's UTC date)

  Use `all/0` for rendering and `resolve/1` to turn an `id` into a usable URL.
  """

  @presets [
    %{
      id: "openfreemap",
      label: "OpenFreeMap Liberty",
      note: "Hosted vector tiles · planet · no key",
      url: "https://tiles.openfreemap.org/styles/liberty",
      download: false,
      url_fn: nil
    },
    %{
      id: "openfreemap-positron",
      label: "OpenFreeMap Positron",
      note: "Light grayscale · planet · hosted",
      url: "https://tiles.openfreemap.org/styles/positron",
      download: false,
      url_fn: nil
    },
    %{
      id: "openfreemap-bright",
      label: "OpenFreeMap Bright",
      note: "Bright · planet · hosted",
      url: "https://tiles.openfreemap.org/styles/bright",
      download: false,
      url_fn: nil
    },
    %{
      id: "protomaps-planet-daily",
      label: "Protomaps planet (daily)",
      note: "~100 GB pmtiles · range-served by R2 · today's UTC build",
      url: nil,
      download: true,
      url_fn: &__MODULE__.protomaps_daily_url/0
    }
  ]

  @doc "Return the full ordered list of presets."
  def all, do: @presets

  @doc """
  Resolve a preset by id and return `{:ok, %{url: url, download: download}}`,
  or `:error` if the id is unknown.
  """
  def resolve(id) do
    case Enum.find(@presets, &(&1.id == id)) do
      nil ->
        :error

      preset ->
        url =
          case preset.url_fn do
            nil -> preset.url
            fun when is_function(fun, 0) -> fun.()
          end

        {:ok, %{url: url, download: preset.download}}
    end
  end

  @doc "Build today's UTC Protomaps daily-planet URL."
  def protomaps_daily_url do
    {{y, m, d}, _} = :calendar.universal_time()
    "https://build.protomaps.com/#{y}#{pad(m)}#{pad(d)}.pmtiles"
  end

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: Integer.to_string(n)
end
