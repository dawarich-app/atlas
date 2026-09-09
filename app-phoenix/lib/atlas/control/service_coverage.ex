defmodule Atlas.Control.ServiceCoverage do
  @moduledoc "Reads service-specific dataset provenance; never uses the draft region selection."

  alias Atlas.Control.RegionCatalog

  @doc "Inspect local data for one known service. Run outside the LiveView process."
  def read(name, opts \\ []) do
    dir = Keyword.get(opts, :data_dir, "/work/data")
    catalog = Keyword.get_lazy(opts, :catalog, &RegionCatalog.all/0)
    probe = Keyword.get(opts, :probe, &probe_header/1)
    inspect_service(name, dir, catalog, probe)
  rescue
    _ -> unknown("Dataset metadata could not be read. The service may still be available.")
  end

  defp inspect_service("libpostal", _dir, _catalog, _probe) do
    %{
      entries: [],
      note:
        "Libpostal uses a language model shared across regions. It does not install a separate map dataset for each region."
    }
  end

  defp inspect_service("photon", dir, catalog, _probe) do
    log = read_tail(Path.join(dir, "photon/logs/photon.log"))
    source = photon_source(log)

    if source && File.dir?(Path.join(dir, "photon/photon_data")) do
      label = photon_label(source, catalog)

      %{
        entries: [
          %{
            label: label,
            kind: "Imported search dataset",
            evidence: "Last successful download recorded by Photon",
            source: source
          }
        ],
        note:
          "Coverage comes from the completed import log, not the region selected in Settings. If data was replaced manually, this record may be outdated."
      }
    else
      unknown(
        "Photon does not report region names in its status API. No completed import record was found locally."
      )
    end
  end

  defp inspect_service(name, dir, catalog, probe) when name in ~w(valhalla otp motis overpass) do
    {relative, kind} =
      case name do
        "valhalla" -> {"valhalla/region.osm.pbf", "Road data"}
        name when name in ~w(otp motis) -> {"otp/region.osm.pbf", "Walking network"}
        "overpass" -> {"osm/current.osm.pbf", "OSM import source"}
      end

    path = Path.join(dir, relative)
    roads = road_entries(path, kind, catalog, probe)
    feeds = if name in ~w(otp motis), do: transit_entries(Path.join(dir, "otp")), else: []

    note =
      case name do
        "overpass" ->
          "This is the local import source. Overpass does not report the region names in its active database; the source alone does not confirm that an import completed."

        name when name in ~w(otp motis) ->
          "Street coverage and transit coverage are separate. These files are on disk; a completed graph build is required before changed data is used. Timetable filenames do not establish their geographic coverage."

        _ ->
          "Coverage is read from the road input on disk. Changed input is used only after the routing graph is rebuilt."
      end

    %{entries: roads ++ feeds, note: note}
  end

  defp inspect_service("placeholder", dir, _catalog, _probe) do
    if File.regular?(Path.join(dir, "placeholder/store.sqlite3")) do
      %{
        entries: [
          %{
            label: "Place database",
            kind: "Administrative places",
            evidence: "Local database present; region coverage not recorded",
            source: "store.sqlite3"
          }
        ],
        note:
          "A custom database may cover different regions. Atlas cannot determine its coverage from the filename."
      }
    else
      unknown("No local place database was found. Region coverage is not recorded.")
    end
  end

  defp inspect_service("whosonfirst", dir, _catalog, _probe) do
    entries =
      Path.wildcard(Path.join(dir, "whosonfirst/*.db"))
      |> Enum.map(
        &%{
          label: Path.basename(&1),
          kind: "Place data",
          evidence: "Local dataset file",
          source: Path.basename(&1)
        }
      )

    %{
      entries: entries,
      note:
        "Dataset files are shown individually. Their presence does not confirm that another service has imported them."
    }
  end

  defp inspect_service(_, _dir, _catalog, _probe),
    do: unknown("Coverage is not available for this service.")

  defp road_entries(path, kind, catalog, probe) do
    if File.regular?(path) do
      case read_manifest(path) do
        [_ | _] = entries ->
          Enum.map(
            entries,
            &Map.merge(&1, %{kind: kind, evidence: "Recorded when this input was prepared"})
          )

        [] ->
          header_entries(path, kind, catalog, probe)
      end
    else
      []
    end
  end

  defp header_entries(path, kind, catalog, probe) do
    case probe.(path) do
      {:ok, %{"header" => header}} ->
        source = get_in(header, ["option", "osmosis_replication_base_url"])
        region = find_source_region(source, catalog)
        label = if region, do: region.label, else: "Region name unavailable"
        boxes = Map.get(header, "boxes", [])
        bounds = Enum.map_join(boxes, "; ", fn box -> Enum.join(box, ", ") end)

        [
          %{
            label: label,
            kind: kind,
            source: source || Path.basename(path),
            evidence: "OSM file header",
            bounds: bounds,
            date: get_in(header, ["option", "osmosis_replication_timestamp"])
          }
        ]

      _ ->
        [
          %{
            label: "Region name unavailable",
            kind: kind,
            source: Path.basename(path),
            evidence: "Input file present; metadata unavailable"
          }
        ]
    end
  end

  defp find_source_region(source, catalog) when is_binary(source) do
    pbf = String.replace_suffix(source, "-updates", "-latest.osm.pbf")
    Enum.find(catalog, &(pbf in &1.pbf_urls))
  end

  defp find_source_region(_, _), do: nil

  defp transit_entries(dir) do
    case File.read(Path.join(dir, "atlas-sources.json")) do
      {:ok, json} ->
        for s <- Jason.decode!(json),
            do: %{
              label: s["name"],
              kind: "Transit timetable",
              source: s["coverage"] || s["id"],
              evidence: "Connected source staged on disk; graph build required"
            }

      {:error, :enoent} ->
        legacy_transit_entries(dir)
    end
  end

  defp legacy_transit_entries(dir) do
    Path.wildcard(Path.join(dir, "*.zip"))
    |> Enum.map(
      &%{
        label: Path.basename(&1),
        kind: "Transit timetable",
        source: Path.basename(&1),
        evidence: "GTFS file on disk"
      }
    )
  end

  @doc "Remember the regions used to prepare inputs, including merged PBFs without region headers."
  def record_inputs(dir, entries, services \\ nil) do
    regions = Enum.map(entries, &%{label: &1.label, source: Enum.join(&1.pbf_urls, ", ")})

    paths =
      ["osm/current.osm.pbf"] ++
        if(is_nil(services) or "valhalla" in services, do: ["valhalla/region.osm.pbf"], else: []) ++
        if(is_nil(services) or Enum.any?(~w(otp motis), &(&1 in services)),
          do: ["otp/region.osm.pbf"],
          else: []
        )

    Enum.reduce_while(
      paths,
      :ok,
      fn relative, :ok ->
        path = Path.join(dir, relative)
        data = %{input: fingerprint(path), regions: regions}

        case File.write(path <> ".regions.json", Jason.encode!(data)) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, :staging, {:coverage_metadata, reason}}}
        end
      end
    )
  end

  defp read_manifest(path) do
    with {:ok, data} <- File.read(path <> ".regions.json"),
         {:ok, %{"input" => input, "regions" => regions}} <- Jason.decode(data),
         true <- input == fingerprint(path),
         true <- is_list(regions) do
      for %{"label" => label, "source" => source} <- regions,
          is_binary(label) and is_binary(source),
          do: %{label: label, source: source}
    else
      _ -> []
    end
  end

  defp fingerprint(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> %{"size" => stat.size, "mtime" => stat.mtime, "ctime" => stat.ctime}
      _ -> nil
    end
  end

  @doc false
  def photon_source(log) do
    log
    |> String.split("\n")
    |> Enum.reduce({nil, nil}, fn line, {pending, completed} ->
      cond do
        String.contains?(line, "Using constructed location for download:") ->
          {download_url(line) || pending, completed}

        String.contains?(line, "download process completed successfully") ->
          {nil, pending || completed}

        true ->
          {pending, completed}
      end
    end)
    |> elem(1)
  end

  defp photon_label(source, catalog) do
    case Regex.run(~r/photon-db-(.+)-\d+\.\d+-latest/, source) do
      [_, name] ->
        case Enum.find(catalog, &(&1.name in [name, "gf:" <> name])) do
          nil -> name |> String.replace("-", " ") |> String.capitalize()
          region -> region.label
        end

      _ ->
        "Photon dataset"
    end
  end

  defp download_url(line) do
    case Regex.run(~r{https://[^\s]+photon-db-[^\s]+\.tar\.bz2}, line) do
      [url] -> url
      _ -> nil
    end
  end

  defp read_tail(path) do
    case File.open(path, [:read, :binary], &read_tail_file/1) do
      {:ok, data} -> data
      _ -> ""
    end
  end

  defp read_tail_file(file) do
    {:ok, size} = :file.position(file, :eof)

    case :file.pread(file, max(0, size - 524_288), 524_288) do
      {:ok, data} -> data
      _ -> ""
    end
  end

  defp probe_header(path) do
    case System.cmd("osmium", ["fileinfo", "-j", path], stderr_to_stdout: true) do
      {json, 0} -> Jason.decode(json)
      _ -> {:error, :unavailable}
    end
  end

  defp unknown(note), do: %{entries: [], note: note}
end
