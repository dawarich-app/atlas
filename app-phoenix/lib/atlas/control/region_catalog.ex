defmodule Atlas.Control.RegionCatalog do
  @moduledoc """
  Loads region presets from `priv/regions/*.env`.

  Each file is a simple `KEY=value` env file. Recognized keys:

    * `REGION_NAME` — short slug (defaults to filename without extension)
    * `REGION_LABEL` — human-readable label
    * `COUNTRY_CODE` — ISO 3166-1 alpha-2
    * `PBF_URL` / `PBF_URLS` — single URL or whitespace-separated list
    * `DEFAULT_LAT` / `DEFAULT_LON` / `DEFAULT_ZOOM` — initial map view

  Ported from `atlas/app/app/services/region_catalog.rb`.
  """

  defstruct [:name, :label, :country_code, :pbf_urls, :default_view]

  @type t :: %__MODULE__{
          name: String.t(),
          label: String.t(),
          country_code: String.t() | nil,
          pbf_urls: [String.t()],
          default_view: %{lat: float() | nil, lon: float() | nil, zoom: integer() | nil}
        }

  @doc """
  List all regions discovered in `priv/regions/`. Returns an empty list when
  the directory is missing. Results are sorted by name for deterministic order.
  """
  def all(dir \\ default_dir()) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".env"))
        |> Enum.map(&load_file(Path.join(dir, &1)))
        |> Enum.sort_by(& &1.name)

      {:error, _} ->
        []
    end
  end

  @doc "Find a region by name. Returns `nil` if not present."
  def find(name, dir \\ default_dir()) do
    Enum.find(all(dir), fn r -> r.name == name end)
  end

  @doc """
  Rough on-disk size hint for a region name, rendered next to region
  presets in the UI. Approximations only — values are derived from the
  Geofabrik PBF sizes as of early 2026.
  """
  def size_hint("planet"), do: "~1.1 TB"
  def size_hint("europe"), do: "~460 GB"
  def size_hint(name) when name in ~w(germany france italy), do: "~75 GB"

  def size_hint(name) when is_binary(name) do
    if String.contains?(name, "multi"), do: "~25 GB", else: "~15 GB"
  end

  def size_hint(_), do: "~15 GB"

  defp default_dir do
    Application.app_dir(:atlas, "priv/regions")
  end

  defp load_file(path) do
    env = parse_env(File.read!(path))
    fallback_name = Path.basename(path, ".env")

    %__MODULE__{
      name: env["REGION_NAME"] || fallback_name,
      label: env["REGION_LABEL"] || fallback_name,
      country_code: env["COUNTRY_CODE"],
      pbf_urls: extract_pbf_urls(env),
      default_view: extract_view(env)
    }
  end

  defp extract_pbf_urls(env) do
    cond do
      is_binary(env["PBF_URLS"]) and String.trim(env["PBF_URLS"]) != "" ->
        env["PBF_URLS"] |> String.split(~r/\s+/, trim: true)

      is_binary(env["PBF_URL"]) ->
        [env["PBF_URL"]]

      true ->
        []
    end
  end

  defp extract_view(env) do
    %{
      lat: parse_float(env["DEFAULT_LAT"]),
      lon: parse_float(env["DEFAULT_LON"]),
      zoom: parse_int(env["DEFAULT_ZOOM"])
    }
  end

  defp parse_env(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      line = String.trim(line)

      cond do
        line == "" -> acc
        String.starts_with?(line, "#") -> acc
        true -> parse_line(line, acc)
      end
    end)
  end

  defp parse_line(line, acc) do
    case Regex.run(~r/\A([A-Z_][A-Z0-9_]*)=(.*)\z/, line) do
      [_, key, raw_value] -> Map.put(acc, key, unquote_value(raw_value))
      _ -> acc
    end
  end

  defp unquote_value(value) do
    cond do
      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        String.slice(value, 1..-2//1)

      true ->
        value
    end
  end

  defp parse_float(nil), do: nil

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end
end
