defmodule Atlas.Maps.Reverse do
  @moduledoc """
  Reverse geocoding orchestrator. Mirrors Rails `ReverseOrchestrator` (single lookup)
  and `BatchReverseGeocoder` (batch).

  ## Batch contract

  Input:

      %{
        coords: [%{lat: 52.5, lon: 13.4, id: "p1"}, ...],
        lang: "en" | nil
      }

  Output:

      {:ok, %{
        results: [
          %{id: "p1", coord: %{lat: 52.5, lon: 13.4}, here: <feature>, admin: <admin>},
          ...
        ],
        cache_hits: non_neg_integer,
        cache_misses: non_neg_integer,
        upstream_errors: non_neg_integer
      }}

  Or, on per-item failure, the result item is:

      %{id: "p1", coord: %{raw_lat: "abc", raw_lon: nil}, error: "lat must be numeric"}

  Over the cap (`@max_coords = 500`):

      {:error, :too_many, 500}
  """
  require Logger
  alias Atlas.Maps.{Place, Result, Upstream.Photon, Upstream.Placeholder, Upstream.Client}

  @max_coords 500
  @grid_decimals 4
  @cache_version "v1"
  # 30 days
  @cache_ttl :timer.hours(720)

  def max_coords, do: @max_coords
  def grid_decimals, do: @grid_decimals

  def lookup(opts) do
    %{lat: lat, lon: lon} = Map.new(opts)
    lang = opts[:lang]

    case Photon.reverse(lat: lat, lon: lon, lang: lang) do
      {:ok, geojson} ->
        feature = normalize_feature(geojson)
        admin = if feature, do: maybe_enrich_admin(feature, lang), else: %{}
        {:ok, %Result{features: %{here: feature, admin: admin}, upstream_status: "ok"}}

      {:error, %Client.Unavailable{} = e} ->
        Logger.warning("photon unavailable: #{Exception.message(e)}")
        {:error, e}

      {:error, %Client.BadResponse{} = e} ->
        Logger.warning("photon bad response: #{Exception.message(e)}")
        {:error, e}
    end
  end

  defp normalize_feature(%{"features" => [feature | _]}), do: Place.from_photon_feature(feature)
  defp normalize_feature(_), do: nil

  defp maybe_enrich_admin(%{admin: admin} = feature, lang) do
    if Map.get(admin, :city) && Map.get(admin, :country) do
      admin
    else
      case Placeholder.admin_for(text: to_string(feature.name), lang: lang) do
        nil -> admin
        placeholder_admin -> Map.merge(placeholder_admin, admin)
      end
    end
  end

  @doc """
  Batch reverse geocode up to `@max_coords` entries.

  Returns `{:ok, summary}` on success (even when individual items fail — those
  produce per-item error entries). Returns `{:error, :too_many, max}` when the
  input exceeds the cap.
  """
  def batch(%{coords: coords} = opts) when is_list(coords) do
    lang = opts[:lang]

    if length(coords) > @max_coords do
      {:error, :too_many, @max_coords}
    else
      do_batch(coords, lang)
    end
  end

  defp do_batch(coords, lang) do
    coords
    |> Enum.with_index()
    |> Task.async_stream(
      fn {coord, _idx} -> process_coord(coord, lang) end,
      max_concurrency: 16,
      ordered: true,
      timeout: 5_000,
      on_timeout: :kill_task
    )
    |> Enum.zip(coords)
    |> Enum.reduce(
      %{results: [], cache_hits: 0, cache_misses: 0, upstream_errors: 0},
      fn
        {{:ok, {:hit, item}}, _coord}, acc ->
          %{acc | results: acc.results ++ [item], cache_hits: acc.cache_hits + 1}

        {{:ok, {:miss_ok, item}}, _coord}, acc ->
          %{acc | results: acc.results ++ [item], cache_misses: acc.cache_misses + 1}

        {{:ok, {:miss_error, item}}, _coord}, acc ->
          %{
            acc
            | results: acc.results ++ [item],
              cache_misses: acc.cache_misses + 1,
              upstream_errors: acc.upstream_errors + 1
          }

        {{:ok, {:bad_input, item}}, _coord}, acc ->
          %{acc | results: acc.results ++ [item], upstream_errors: acc.upstream_errors + 1}

        {{:exit, _}, coord}, acc ->
          {raw_lat, raw_lon, id} = raw_fields(coord)
          # Rails timeout shape: here: nil, admin: %{}
          item = %{
            id: id,
            coord: %{lat: raw_lat, lon: raw_lon},
            here: nil,
            admin: %{}
          }

          %{acc | results: acc.results ++ [item], upstream_errors: acc.upstream_errors + 1}
      end
    )
    |> then(&{:ok, &1})
  end

  defp process_coord(coord, lang) do
    {raw_lat, raw_lon, id} = raw_fields(coord)

    with {:ok, lat} <- coerce_float(raw_lat, "lat"),
         {:ok, lon} <- coerce_float(raw_lon, "lon") do
      key = cache_key(lat, lon, lang)
      do_lookup_with_cache(key, id, lat, lon, lang)
    else
      {:error, msg} ->
        {:bad_input, %{id: id, coord: %{raw_lat: raw_lat, raw_lon: raw_lon}, error: msg}}
    end
  end

  defp raw_fields(coord) when is_map(coord) do
    {Map.get(coord, "lat") || Map.get(coord, :lat), Map.get(coord, "lon") || Map.get(coord, :lon),
     Map.get(coord, "id") || Map.get(coord, :id)}
  end

  defp coerce_float(nil, name), do: {:error, "#{name} must be numeric"}
  defp coerce_float(v, _) when is_number(v), do: {:ok, v * 1.0}

  defp coerce_float(v, name) when is_binary(v) do
    case Float.parse(v) do
      {f, ""} -> {:ok, f}
      {f, _} -> {:ok, f}
      :error -> {:error, "#{name} must be numeric"}
    end
  end

  defp coerce_float(_, name), do: {:error, "#{name} must be numeric"}

  defp do_lookup_with_cache(key, id, lat, lon, lang) do
    case safe_cache_get(key) do
      {:ok, %{here: here, admin: admin}} ->
        {:hit, %{id: id, coord: %{lat: lat, lon: lon}, here: here, admin: admin}}

      :miss ->
        perform_lookup_and_cache(key, id, lat, lon, lang)
    end
  end

  defp perform_lookup_and_cache(key, id, lat, lon, lang) do
    case lookup(lat: lat, lon: lon, lang: lang) do
      {:ok, %Result{features: %{here: here, admin: admin}, upstream_status: "ok"}} ->
        Cachex.put(:reverse_cache, key, %{here: here, admin: admin}, expire: @cache_ttl)
        {:miss_ok, %{id: id, coord: %{lat: lat, lon: lon}, here: here, admin: admin}}

      _ ->
        {:miss_error, %{id: id, coord: %{lat: lat, lon: lon}, here: nil, admin: %{}}}
    end
  end

  defp safe_cache_get(key) do
    case Cachex.get(:reverse_cache, key) do
      {:ok, nil} -> :miss
      {:ok, value} -> {:ok, value}
      {:error, _} -> :miss
    end
  end

  defp cache_key(lat, lon, lang) do
    snapped_lat = Float.round(lat, @grid_decimals)
    snapped_lon = Float.round(lon, @grid_decimals)
    "rg:#{@cache_version}:#{snapped_lat}:#{snapped_lon}:#{lang || "default"}"
  end
end
