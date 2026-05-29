defmodule Atlas.Maps.Geocode do
  @moduledoc """
  Dual-mode geocode dispatch — forward via Search (when `q` is given) or
  reverse via Reverse (when `lat+lon` are given). Mirrors Rails behavior.
  """
  alias Atlas.Maps.{Search, Reverse}

  @doc """
  Returns one of:

      {:ok, :forward, %Result{features: [<features>], upstream_status: _}}
      {:ok, :reverse, %Result{features: %{here, admin}, upstream_status: _}}
      {:error, :missing, "q or lat+lon"}
      {:error, %Client.*{}}
  """
  def lookup(opts) do
    q = opts[:query]
    lat = opts[:lat]
    lon = opts[:lon]
    lang = opts[:lang]

    cond do
      is_binary(q) and String.trim(q) != "" ->
        forward_lookup(q, lat, lon, lang, opts[:limit] || 8)

      is_number(lat) and is_number(lon) ->
        reverse_lookup(lat, lon, lang)

      true ->
        {:error, :missing, "q or lat+lon"}
    end
  end

  defp forward_lookup(q, lat, lon, lang, limit) do
    case Search.autocomplete(%{query: String.trim(q), limit: limit, lang: lang, lat: lat, lon: lon}) do
      {:ok, result} -> {:ok, :forward, result}
      err -> err
    end
  end

  defp reverse_lookup(lat, lon, lang) do
    case Reverse.lookup(lat: lat, lon: lon, lang: lang) do
      {:ok, result} -> {:ok, :reverse, result}
      err -> err
    end
  end
end
