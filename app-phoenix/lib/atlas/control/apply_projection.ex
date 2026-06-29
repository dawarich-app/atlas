defmodule Atlas.Control.ApplyProjection do
  @moduledoc """
  Projects disk usage and first-boot hours for a selected region set, plus
  computes per-service intents (enable/disable) based on the projected service
  configuration.

  Ported from Rails `app/services/apply_projection.rb` so the Phoenix Admin
  Apply flow can show the same confirmation modal.
  """

  @city_disk %{
    "photon" => 8.0,
    "placeholder" => 4.0,
    "libpostal" => 0.0,
    "valhalla" => 1.0,
    "overpass" => 4.0,
    "otp" => 1.0
  }

  @country_disk %{
    "photon" => 8.0,
    "placeholder" => 4.0,
    "libpostal" => 0.0,
    "valhalla" => 15.0,
    "overpass" => 45.0,
    "otp" => 5.0
  }

  @subregion_disk %{
    "photon" => 8.0,
    "placeholder" => 4.0,
    "libpostal" => 0.0,
    "valhalla" => 5.0,
    "overpass" => 18.0,
    "otp" => 2.0
  }

  @continent_disk %{
    "photon" => 30.0,
    "placeholder" => 4.0,
    "libpostal" => 0.0,
    "valhalla" => 115.0,
    "overpass" => 280.0,
    "otp" => 30.0
  }

  @planet_disk %{
    "photon" => 110.0,
    "placeholder" => 4.0,
    "libpostal" => 0.0,
    "valhalla" => 250.0,
    "overpass" => 700.0,
    "otp" => 50.0
  }

  @hours %{
    "photon" => 2.0,
    "placeholder" => 1.5,
    "libpostal" => 0.05,
    "valhalla" => 1.5,
    "overpass" => 6.0,
    "otp" => 1.0
  }

  @doc """
  Build a projection for `regions` (list of names or %RegionCatalog{} structs).

  `intents` is a list of `%{name: String.t(), enabled: boolean}` representing
  user-proposed service toggles. The projection sums disk for the *projected*
  enabled set (current enabled - intents-disabled + intents-enabled).
  """
  def summary(regions, intents \\ []) when is_list(regions) and is_list(intents) do
    catalog_regions = Enum.map(regions, &resolve_region/1)
    table = scaling_table(catalog_regions)

    enabled_services = projected_service_names(intents)

    lines =
      Enum.map(enabled_services, fn svc ->
        %{
          name: svc,
          disk_gb: Map.get(table, svc, 0.0),
          hours: Map.get(@hours, svc, 0.0)
        }
      end)

    total_disk_gb =
      lines |> Enum.map(& &1.disk_gb) |> Enum.sum() |> ensure_float() |> Float.round(1)

    first_boot_hours =
      lines |> Enum.map(& &1.hours) |> max_or_zero() |> ensure_float() |> Float.round(1)

    %{
      total_disk_gb: total_disk_gb,
      first_boot_hours: first_boot_hours,
      lines: lines,
      service_intents: normalize_intents(intents)
    }
  end

  defp normalize_intents(intents) do
    Enum.map(intents, fn
      %{name: name, enabled: enabled} = i ->
        %{name: name, enabled: !!enabled, reason: Map.get(i, :reason, "")}

      %{"name" => name, "enabled" => enabled} = i ->
        %{name: name, enabled: !!enabled, reason: Map.get(i, "reason", "")}
    end)
  end

  defp projected_service_names(intents) do
    current =
      try do
        Atlas.Control.Service
        |> Atlas.Repo.all()
        |> Enum.filter(& &1.enabled)
        |> Enum.map(& &1.name)
        |> MapSet.new()
      rescue
        _ -> MapSet.new()
      end

    Enum.reduce(intents, current, fn intent, acc ->
      name = intent_name(intent)
      enabled = intent_enabled(intent)

      cond do
        is_nil(name) -> acc
        enabled -> MapSet.put(acc, name)
        true -> MapSet.delete(acc, name)
      end
    end)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  defp intent_name(%{name: n}), do: n
  defp intent_name(%{"name" => n}), do: n
  defp intent_name(_), do: nil
  defp intent_enabled(%{enabled: e}), do: !!e
  defp intent_enabled(%{"enabled" => e}), do: !!e
  defp intent_enabled(_), do: false

  defp resolve_region(%Atlas.Control.RegionCatalog{} = r), do: r

  defp resolve_region(name) when is_binary(name) do
    Atlas.Control.RegionCatalog.find(name) ||
      %Atlas.Control.RegionCatalog{name: name, label: name, pbf_urls: []}
  end

  defp scaling_table([]), do: @city_disk

  defp scaling_table([first | _]) do
    case classify(first) do
      :city -> @city_disk
      :subregion -> @subregion_disk
      :country -> @country_disk
      :continent -> @continent_disk
      :planet -> @planet_disk
    end
  end

  defp classify(%{name: "planet"}), do: :planet
  defp classify(%{kind: "planet"}), do: :planet
  defp classify(%{kind: "continent"}), do: :continent
  defp classify(%{kind: "country"}), do: :country
  defp classify(%{kind: "subregion"}), do: :subregion
  defp classify(%{kind: "city"}), do: :city
  defp classify(%{name: "europe"}), do: :continent

  defp classify(%{name: name})
       when name in ["germany", "france", "italy"],
       do: :country

  defp classify(%{country_code: cc, pbf_urls: urls})
       when is_binary(cc) and is_list(urls) do
    if Enum.any?(urls, &String.contains?(&1, "geofabrik")),
      do: :country,
      else: :city
  end

  defp classify(_), do: :city

  defp max_or_zero([]), do: 0.0
  defp max_or_zero(list), do: Enum.max(list)

  defp ensure_float(n) when is_float(n), do: n
  defp ensure_float(n) when is_integer(n), do: n * 1.0
end
