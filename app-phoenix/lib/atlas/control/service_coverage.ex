defmodule Atlas.Control.ServiceCoverage do
  @moduledoc "Reads service-specific dataset provenance; never uses the draft region selection."

  alias Atlas.Control.{Health, RegionCatalog}
  alias Atlas.Settings

  @region_kinds ["Imported search dataset", "Road data", "OSM import source", "Walking network"]

  @doc "Build public, capability-oriented coverage from installed datasets and live health."
  def summary(opts \\ []) do
    health = Keyword.get_lazy(opts, :health, &Health.summary/0)
    transit_service = Keyword.get_lazy(opts, :transit_backend, &Settings.transit_backend/0)

    read_opts =
      opts
      |> Keyword.drop([:health, :transit_backend, :valhalla_regions])
      |> Keyword.put_new(:catalog, [])
      |> Keyword.put(:probe, &skip_header_probe/1)

    statuses = Map.get(health, :capabilities, %{})

    routing =
      "valhalla"
      |> capability(Map.get(statuses, "routing", "down"), read_opts)
      |> use_declared_regions(valhalla_regions(opts), "VALHALLA_COVERAGE_REGIONS")

    %{
      capabilities: %{
        geocoding: capability("photon", Map.get(statuses, "geocoding", "down"), read_opts),
        routing: routing,
        map_matching: Map.put(routing, :inherits, "routing"),
        pois: capability("overpass", Map.get(statuses, "pois", "down"), read_opts),
        transit:
          transit_capability(
            transit_service,
            Map.get(statuses, "transit", "down"),
            read_opts
          )
      }
    }
  end

  @doc "Inspect local data for one known service. Run outside the LiveView process."
  def read(name, opts \\ []) do
    dir = Keyword.get(opts, :data_dir, "/work/data")
    catalog = Keyword.get_lazy(opts, :catalog, &RegionCatalog.all/0)
    probe = Keyword.get(opts, :probe, &probe_header/1)
    inspect_service(name, dir, catalog, probe)
  rescue
    _ -> unknown("Dataset metadata could not be read. The service may still be available.")
  end

  defp capability(service, status, opts) do
    coverage = read(service, opts)
    regions = region_labels(coverage.entries)

    %{
      available: status == "up",
      coverage_status: if(regions == [], do: "unknown", else: "known"),
      datasets: coverage.entries,
      note: coverage.note,
      regions: regions,
      service: service,
      status: status
    }
  end

  defp transit_capability(service, status, opts) do
    capability = capability(service, status, opts)

    feeds =
      capability.datasets
      |> Enum.filter(&(&1.kind == "Transit timetable"))
      |> Enum.map(&transit_feed/1)

    Map.put(capability, :transit_feeds, feeds)
  end

  defp region_labels(entries) do
    entries
    |> Enum.filter(&(&1.kind in @region_kinds))
    |> Enum.map(&present_string(&1.label))
    |> Enum.reject(&(&1 in [nil, "Region name unavailable", "Photon dataset"]))
    |> Enum.uniq()
  end

  defp transit_feed(entry) do
    %{
      coverage: entry.source,
      evidence: entry.evidence,
      name: entry.label
    }
  end

  defp valhalla_regions(opts) do
    opts
    |> Keyword.get_lazy(:valhalla_regions, fn -> System.get_env("VALHALLA_COVERAGE_REGIONS") end)
    |> normalize_regions()
  end

  defp normalize_regions(regions) when is_binary(regions) do
    regions
    |> String.split(",")
    |> normalize_regions()
  end

  defp normalize_regions(regions) when is_list(regions) do
    regions
    |> Enum.map(&present_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_regions(_regions), do: []

  defp use_declared_regions(%{regions: [_ | _]} = capability, _regions, _source),
    do: capability

  defp use_declared_regions(capability, [], _source), do: capability

  defp use_declared_regions(capability, regions, source) do
    datasets =
      Enum.map(regions, fn region ->
        %{
          label: region,
          kind: "Declared service coverage",
          evidence: "Declared by the Atlas operator; not inspected from the remote service",
          source: source
        }
      end)

    %{
      capability
      | coverage_status: "known",
        datasets: capability.datasets ++ datasets,
        note:
          capability.note <>
            " Region coverage is declared by the operator via #{source}.",
        regions: regions
    }
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
    with {:ok, json} <- File.read(Path.join(dir, "atlas-sources.json")),
         {:ok, sources} when is_list(sources) <- Jason.decode(json) do
      Enum.flat_map(sources, &transit_entry/1)
    else
      {:error, :enoent} ->
        legacy_transit_entries(dir)

      _ ->
        []
    end
  end

  defp transit_entry(source) when is_map(source) do
    id = present_string(source["id"])
    label = present_string(source["name"]) || id
    coverage = present_string(source["coverage"]) || id

    if label && coverage do
      [
        %{
          label: label,
          kind: "Transit timetable",
          source: coverage,
          evidence: "Connected source staged on disk; graph build required"
        }
      ]
    else
      []
    end
  end

  defp transit_entry(_), do: []

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      string -> string
    end
  end

  defp present_string(_), do: nil

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

  defp skip_header_probe(_path), do: {:error, :not_probed}

  defp unknown(note), do: %{entries: [], note: note}
end
