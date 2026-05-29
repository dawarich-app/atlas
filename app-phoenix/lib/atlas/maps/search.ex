defmodule Atlas.Maps.Search do
  require Logger
  alias Atlas.Maps.{Result, Upstream.Libpostal, Upstream.Photon, Upstream.Placeholder, Upstream.Client}

  def autocomplete(opts) do
    %{query: query, limit: limit} = opts
    lang = Map.get(opts, :lang)
    lat = Map.get(opts, :lat)
    lon = Map.get(opts, :lon)
    bbox = Map.get(opts, :bbox)

    photon_query = Libpostal.normalize(query) |> Map.fetch!(:query)

    case Photon.search(query: photon_query, limit: limit, lang: lang, lat: lat, lon: lon, bbox: bbox) do
      {:ok, geojson} ->
        features =
          geojson
          |> normalize_features()
          |> Task.async_stream(
               &enrich_with_placeholder(&1, lang),
               max_concurrency: 8, ordered: true, timeout: 3_000, on_timeout: :kill_task
             )
          |> Enum.map(fn
               {:ok, feature} -> feature
               {:exit, _} -> nil
             end)
          |> Enum.reject(&is_nil/1)

        {:ok, %Result{features: features, upstream_status: "ok"}}

      {:error, %Client.Unavailable{} = e} ->
        Logger.warning("photon unavailable: #{Exception.message(e)}")
        {:error, e}

      {:error, %Client.BadResponse{} = e} ->
        Logger.warning("photon bad response: #{Exception.message(e)}")
        {:error, e}
    end
  end

  defp normalize_features(%{"features" => features}) when is_list(features), do: Enum.map(features, &normalize_feature/1)
  defp normalize_features(_), do: []

  defp normalize_feature(%{"properties" => props, "geometry" => geom}) do
    coords = Map.get(geom, "coordinates", [])
    [lon, lat | _] = coords ++ [nil, nil]

    admin =
      %{
        country: props["country"],
        state: props["state"],
        county: props["county"],
        city: props["city"],
        postcode: props["postcode"]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

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
      admin: admin
    }
  end

  defp enrich_with_placeholder(feature, lang) do
    if Map.has_key?(feature.admin, :country) and Map.has_key?(feature.admin, :city) do
      feature
    else
      case Placeholder.admin_for(text: to_string(feature.name), lang: lang) do
        nil -> feature
        placeholder_admin -> %{feature | admin: Map.merge(placeholder_admin, feature.admin)}
      end
    end
  end
end
