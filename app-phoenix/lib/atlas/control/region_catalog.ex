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

  defstruct [
    :name,
    :label,
    :country_code,
    :pbf_urls,
    :default_view,
    :kind,
    :parent,
    :pbf_bytes,
    :gtfs_url,
    :gtfs_name,
    iso: []
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          label: String.t(),
          country_code: String.t() | nil,
          pbf_urls: [String.t()],
          default_view: %{lat: float() | nil, lon: float() | nil, zoom: integer() | nil},
          kind: String.t() | nil,
          parent: String.t() | nil,
          pbf_bytes: non_neg_integer() | nil,
          gtfs_url: String.t() | nil,
          gtfs_name: String.t() | nil,
          iso: [String.t()]
        }

  @doc """
  List all regions discovered in `priv/regions/`. Returns an empty list when
  the directory is missing. Results are sorted by name for deterministic order.
  """
  def all(dir \\ default_dir()) do
    curated =
      case File.ls(dir) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.ends_with?(&1, ".env"))
          |> Enum.map(&load_file(Path.join(dir, &1)))

        {:error, _} ->
          []
      end

    baked = load_catalog(dir)
    baked_by_url = Map.new(baked, fn b -> {primary_url(b), b} end)

    # A curated preset that shares a PBF URL with a baked entry is the SAME
    # download — adopt the baked entry's hierarchy position (parent/kind) so the
    # preset nests correctly, keep the curated name (apply/transit config keys on
    # it), and drop the baked duplicate.
    enriched = Enum.map(curated, &enrich_from_baked(&1, baked_by_url))

    curated_names = MapSet.new(curated, & &1.name)
    url_to_curated = curated |> Enum.map(&{primary_url(&1), &1.name}) |> Enum.reject(&(elem(&1, 0) == nil)) |> Map.new()

    # Baked entries superseded by a curated preset of a different name → rename
    # their references so children don't orphan when the baked entry is dropped.
    rename =
      for b <- baked,
          u = primary_url(b),
          not is_nil(u),
          cname = Map.get(url_to_curated, u),
          not is_nil(cname),
          cname != b.name,
          into: %{},
          do: {b.name, cname}

    baked_kept =
      Enum.reject(baked, fn b ->
        MapSet.member?(curated_names, b.name) or Map.has_key?(rename, b.name)
      end)

    (enriched ++ baked_kept)
    |> Enum.map(&reparent(&1, rename))
    |> Enum.sort_by(& &1.name)
  end

  defp reparent(%__MODULE__{parent: p} = e, rename) when is_binary(p) do
    case Map.get(rename, p) do
      nil -> e
      new_parent -> %{e | parent: new_parent}
    end
  end

  defp reparent(e, _rename), do: e

  defp primary_url(%__MODULE__{pbf_urls: [u | _]}), do: u
  defp primary_url(_), do: nil

  defp enrich_from_baked(%__MODULE__{} = curated, baked_by_url) do
    case Map.get(baked_by_url, primary_url(curated)) do
      nil ->
        curated

      %__MODULE__{} = baked ->
        %{
          curated
          | parent: baked.parent,
            kind: curated.kind || baked.kind,
            country_code: curated.country_code || baked.country_code,
            pbf_bytes: curated.pbf_bytes || baked.pbf_bytes,
            iso: if(curated.iso in [nil, []], do: baked.iso, else: curated.iso)
        }
    end
  end

  @doc "Find a region by name. Returns `nil` if not present."
  def find(name, dir \\ default_dir()) do
    Enum.find(all(dir), fn r -> r.name == name end)
  end

  @doc "Parentless entries (continents + curated presets), sorted by label."
  def roots(dir \\ default_dir()) do
    all(dir) |> Enum.filter(&is_nil(&1.parent)) |> Enum.sort_by(& &1.label)
  end

  @doc "Entries whose `parent` equals `name`, sorted by label."
  def children(name, dir \\ default_dir()) do
    all(dir) |> Enum.filter(&(&1.parent == name)) |> Enum.sort_by(& &1.label)
  end

  @doc """
  Build a parent-keyed index of the whole catalog in a single `all/1` read.

  Returns `%{parent_name => [%RegionCatalog{}, ...]}` where each entry is grouped
  under its `parent` field; roots (`parent: nil`) group under the `nil` key. Each
  child list is sorted by `label`, matching `roots/1`/`children/1` ordering.
  """
  def tree_index(dir \\ default_dir()) do
    dir
    |> all()
    |> Enum.group_by(& &1.parent)
    |> Map.new(fn {parent, entries} -> {parent, Enum.sort_by(entries, & &1.label)} end)
  end

  @doc "Case-insensitive match against label, name, and ISO codes."
  def search(query, dir \\ default_dir()) do
    q = String.downcase(String.trim(query))

    if q == "" do
      []
    else
      all(dir)
      |> Enum.filter(fn r ->
        haystack = [r.label, r.name | r.iso || []] |> Enum.join(" ") |> String.downcase()
        String.contains?(haystack, q)
      end)
      |> Enum.sort_by(& &1.label)
    end
  end

  @doc """
  Load `catalog.json` (the baked, generated catalog) from `dir`. Returns `[]`
  when the file is missing or malformed — the admin panel must never crash on a
  bad catalog.
  """
  def load_catalog(dir \\ default_dir()) do
    path = Path.join(dir, "catalog.json")

    with {:ok, body} <- File.read(path),
         {:ok, entries} when is_list(entries) <- Jason.decode(body) do
      Enum.map(entries, &from_catalog_entry/1)
    else
      _ -> []
    end
  end

  defp from_catalog_entry(e) do
    %__MODULE__{
      name: e["name"],
      label: e["label"] || e["name"],
      country_code: e["country_code"],
      pbf_urls: List.wrap(e["pbf_url"]),
      default_view: %{lat: nil, lon: nil, zoom: nil},
      kind: e["kind"],
      parent: e["parent"],
      pbf_bytes: e["pbf_bytes"],
      iso: e["iso"] || []
    }
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

  @doc """
  Human size for a region. Uses the real baked `pbf_bytes` when present;
  otherwise a coarse tier by `kind` (continent/country/subregion/city/planet),
  falling back to the name-based `size_hint/1` for curated presets without a
  kind.
  """
  def size_label(%__MODULE__{pbf_bytes: bytes}) when is_integer(bytes),
    do: format_bytes(bytes)

  def size_label(%__MODULE__{pbf_bytes: nil, kind: kind, name: name}),
    do: kind_size(kind) || size_hint(name)

  defp kind_size("planet"), do: "~1.1 TB"
  defp kind_size("continent"), do: "~460 GB"
  defp kind_size("country"), do: "~75 GB"
  defp kind_size("subregion"), do: "~25 GB"
  defp kind_size("city"), do: "~15 GB"
  defp kind_size(_), do: nil

  defp format_bytes(b) when b >= 1_000_000_000_000, do: "#{round1(b / 1_000_000_000_000)} TB"
  defp format_bytes(b) when b >= 1_000_000_000, do: "#{round1(b / 1_000_000_000)} GB"
  defp format_bytes(b) when b >= 1_000_000, do: "#{round1(b / 1_000_000)} MB"
  defp format_bytes(b), do: "#{round1(b / 1_000)} KB"

  defp round1(f), do: :erlang.float_to_binary(Float.round(f * 1.0, 1), decimals: 1)

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
      default_view: extract_view(env),
      gtfs_url: presence(env["GTFS_URL"]),
      gtfs_name: presence(env["GTFS_NAME"]),
      iso: []
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

  defp presence(nil), do: nil

  defp presence(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      trimmed -> trimmed
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
