defmodule Atlas.Control.OtpBuildConfig do
  @moduledoc """
  Produces OTP's `build-config.json` — specifically `osmDefaults.timeZone`,
  which OTP uses to resolve `opening_hours` and conditional access restrictions
  while parsing the OSM extract. Without it OTP logs

      Missing time zone for OSM source file:/var/opentripplanner/region.osm.pbf
      — time-restricted entities will not be created

  and every time-based restriction is silently dropped from the street graph.

  OTP accepts exactly one zone for an extract, but an apply can merge several
  regions into one PBF. So a zone is emitted only when every selected region
  agrees on one, and `:ambiguous` otherwise: a wrong zone is worse than the
  warning, because it shifts every restriction by whole hours without saying so.

  ## The table

  `priv/country_zones.exs` maps ISO 3166-1 alpha-2 to `{zone, signature}` and is
  generated, not hand-written — see `priv/scripts/gen_country_zones.py`. A
  country appears only when all of its IANA zones hold the same UTC offset all
  year; the zone kept is the one `zone.tab` lists first, that country's primary.

  The signature is that offset timeline, written as its transition points
  (`"+01:00@0,+02:00@30,+01:00@100"`). Countries with equal signatures keep the
  same clock all year, so either zone answers opening hours identically — which
  is what lets Berlin + Vienna resolve while Berlin + London stays ambiguous.

  Excluded by construction: countries spanning real offset differences (US, CA,
  AU, BR, RU, MX, ID, ES, PT, UA, CN, ...). Kept despite a nominal split:
  Germany (Europe/Busingen) and Cyprus (Asia/Famagusta) among others, whose
  twins have tracked the primary zone to the minute for decades.
  """

  alias Atlas.Control.RegionCatalog

  @path Path.expand("../../../priv/country_zones.exs", __DIR__)
  @external_resource @path
  @country_zones Code.eval_file(@path) |> elem(0)

  @doc """
  The generated country table, as `%{alpha_2 => {zone, signature}}`.
  """
  @spec country_zones() :: %{optional(String.t()) => {String.t(), String.t()}}
  def country_zones, do: @country_zones

  @doc """
  The one IANA zone that answers opening hours for every given region, or
  `:ambiguous` when no single zone does.
  """
  @spec resolve([RegionCatalog.t()]) :: {:ok, String.t()} | :ambiguous
  def resolve([]), do: :ambiguous

  def resolve(entries) do
    entries
    |> Enum.reduce_while([], fn entry, acc ->
      case lookup(entry.country_code) do
        nil -> {:halt, :ambiguous}
        pair -> {:cont, [pair | acc]}
      end
    end)
    |> agree()
  end

  @doc """
  The `build-config.json` body pinning `zone` for every OSM feed.
  """
  @spec render(String.t()) :: String.t()
  def render(zone) when is_binary(zone) do
    Jason.encode!(%{"osmDefaults" => %{"timeZone" => zone}}, pretty: true) <> "\n"
  end

  defp agree(:ambiguous), do: :ambiguous

  defp agree(pairs) do
    case Enum.uniq_by(pairs, fn {_zone, signature} -> signature end) do
      # Sorted rather than "first selected": selection order is the UI's, and a
      # build config that changes with click order is a config that drifts.
      [_single] -> {:ok, pairs |> Enum.map(&elem(&1, 0)) |> Enum.min()}
      _several -> :ambiguous
    end
  end

  defp lookup(code) when is_binary(code) do
    Map.get(@country_zones, code |> String.trim() |> String.downcase())
  end

  defp lookup(_), do: nil
end
