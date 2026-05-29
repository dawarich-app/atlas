defmodule Atlas.Maps.Reverse do
  require Logger
  alias Atlas.Maps.{Result, Upstream.Photon, Upstream.Placeholder, Upstream.Client}

  @max_coords 1000
  @grid_decimals 6

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

  defp normalize_feature(%{"features" => [feature | _]}), do: do_normalize(feature)
  defp normalize_feature(_), do: nil

  defp do_normalize(%{"properties" => props, "geometry" => geom}) do
    coords = Map.get(geom, "coordinates", [])
    [lon, lat | _] = coords ++ [nil, nil]

    %{
      id: [props["osm_type"], props["osm_id"]] |> Enum.reject(&is_nil/1) |> Enum.join(":"),
      name: props["name"],
      label:
        [props["name"], props["city"], props["state"], props["country"]]
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.join(", "),
      type: props["osm_value"] || props["osm_key"],
      coords: %{lon: lon, lat: lat},
      admin:
        %{
          country: props["country"],
          state: props["state"],
          county: props["county"],
          city: props["city"],
          postcode: props["postcode"]
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
    }
  end

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

  def batch(%{coords: coords} = opts) do
    lang = opts[:lang]
    capped = Enum.take(coords, @max_coords)

    keys = Enum.map(capped, &grid_key(&1, lang))

    keys
    |> Task.async_stream(
         fn key -> lookup_with_cache(key) end,
         max_concurrency: 16, ordered: true, timeout: 5_000, on_timeout: :kill_task
       )
    |> Enum.zip(capped)
    |> Enum.reduce(%{results: [], cache_hits: 0, cache_misses: 0, upstream_errors: 0}, fn
      {{:ok, {:hit, result}}, _coord}, acc ->
        %{acc | results: acc.results ++ [result], cache_hits: acc.cache_hits + 1}

      {{:ok, {:miss_ok, result}}, _coord}, acc ->
        %{acc | results: acc.results ++ [result], cache_misses: acc.cache_misses + 1}

      {{:ok, :miss_error}, coord}, acc ->
        %{acc | results: acc.results ++ [%{coord: coord, error: "upstream"}], upstream_errors: acc.upstream_errors + 1}

      {{:exit, _}, coord}, acc ->
        %{acc | results: acc.results ++ [%{coord: coord, error: "timeout"}], upstream_errors: acc.upstream_errors + 1}
    end)
  end

  defp grid_key(%{lat: lat, lon: lon}, lang) do
    {Float.round(lat / 1.0, @grid_decimals), Float.round(lon / 1.0, @grid_decimals), lang}
  end

  defp lookup_with_cache({lat, lon, lang} = key) do
    case Cachex.get(:reverse_cache, key) do
      {:ok, nil} ->
        case lookup(lat: lat, lon: lon, lang: lang) do
          {:ok, %{upstream_status: "ok"} = result} ->
            Cachex.put(:reverse_cache, key, result.features)
            {:miss_ok, %{coord: %{lat: lat, lon: lon}, here: result.features.here, admin: result.features.admin}}

          _ ->
            :miss_error
        end

      {:ok, cached} ->
        {:hit, %{coord: %{lat: lat, lon: lon}, here: cached.here, admin: cached.admin}}

      {:error, _} ->
        case lookup(lat: lat, lon: lon, lang: lang) do
          {:ok, %{upstream_status: "ok"} = result} ->
            {:miss_ok, %{coord: %{lat: lat, lon: lon}, here: result.features.here, admin: result.features.admin}}

          _ ->
            :miss_error
        end
    end
  end
end
