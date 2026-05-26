defmodule Atlas.Maps.Reverse do
  require Logger
  alias Atlas.Maps.{Result, Upstream.Photon, Upstream.Placeholder, Upstream.Client}

  def lookup(opts) do
    %{lat: lat, lon: lon} = Map.new(opts)
    lang = opts[:lang]

    case Photon.reverse(lat: lat, lon: lon, lang: lang) do
      {:ok, geojson} ->
        feature = normalize_feature(geojson)
        admin = if feature, do: maybe_enrich_admin(feature, lang), else: %{}
        %Result{features: %{here: feature, admin: admin}, upstream_status: "ok"}

      {:error, %Client.Unavailable{} = e} ->
        Logger.warning("photon unavailable: #{Exception.message(e)}")
        %Result{features: %{here: nil, admin: %{}}, upstream_status: "unavailable"}

      {:error, %Client.BadResponse{} = e} ->
        Logger.warning("photon bad response: #{Exception.message(e)}")
        %Result{features: %{here: nil, admin: %{}}, upstream_status: "error"}
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
      label: [props["name"], props["city"], props["country"]] |> Enum.reject(&is_nil/1) |> Enum.join(", "),
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
end
