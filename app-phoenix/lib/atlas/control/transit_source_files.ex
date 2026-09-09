defmodule Atlas.Control.TransitSourceFiles do
  @moduledoc "Validated timetable downloads and deterministic MOTIS/OTP feed configuration."
  alias Atlas.Control.TransitSources
  @required ~w(agency.txt stops.txt routes.txt trips.txt stop_times.txt)

  # Existing downloads stay usable until their replacement passes validation.
  def prepare(sources, data_dir, progress, fetch \\ &fetch/3) do
    dir = Path.join(data_dir, "gtfs/atlas-feeds")
    File.mkdir_p!(dir)

    Enum.reduce(sources, [], fn source, usable ->
      path = Path.join(dir, cache_name(source))
      temp = path <> ".next"
      File.rm(temp)
      File.rm(temp <> ".partial")
      progress.(source["name"])

      result = download(source, temp, path, fetch)

      old = TransitSources.statuses()[source["id"]] || %{}

      status =
        case result do
          :ok ->
            %{"downloaded_at" => DateTime.to_iso8601(DateTime.utc_now()), "error" => nil}

          _ ->
            Map.put(
              old,
              "error",
              "Download or GTFS validation failed. The last valid timetable is kept, if available."
            )
        end

      TransitSources.put_status(source["id"], status)
      File.rm(temp)
      File.rm(temp <> ".partial")
      if File.exists?(path), do: usable ++ [source], else: usable
    end)
  end

  defp download(source, temp, path, fetch) do
    with {:ok, _} <- fetch.(source, temp, fn _, _ -> :ok end),
         :ok <- validate_zip(temp),
         do: File.rename(temp, path)
  rescue
    _ -> {:error, :download_failed}
  end

  def cache_name(source) do
    hash =
      :crypto.hash(:sha256, source["url"]) |> Base.encode16(case: :lower) |> binary_part(0, 16)

    source["id"] <> "-" <> hash <> ".gtfs.zip"
  end

  def fetch(source, path, progress) do
    Atlas.Control.Downloader.fetch(source["url"], path, progress,
      headers: TransitSources.headers(source)
    )
  end

  def validate_zip(path) do
    with {:ok, entries} <- :zip.table(String.to_charlist(path)) do
      files = for {:zip_file, name, _, _, _, _} <- entries, do: List.to_string(name)

      if Enum.all?(@required, &(&1 in files)) and
           Enum.any?(~w(calendar.txt calendar_dates.txt), &(&1 in files)),
         do: :ok,
         else: {:error, :missing_gtfs_tables}
    end
  end

  def stage(sources, data_dir) do
    otp = Path.join(data_dir, "otp")
    File.mkdir_p!(Path.join(otp, "atlas-feeds"))

    Enum.each(sources, fn s ->
      name = s["id"] <> ".gtfs.zip"

      File.cp!(
        Path.join(data_dir, "gtfs/atlas-feeds/" <> cache_name(s)),
        Path.join(otp, "atlas-feeds/" <> name)
      )
    end)

    atomic_write(Path.join(otp, "motis-datasets.yml"), motis(sources))

    update_json(Path.join(otp, "build-config.json"), fn config ->
      Map.put(
        config,
        "transitFeeds",
        Enum.map(sources, fn s ->
          %{
            "type" => "gtfs",
            "feedId" => s["id"],
            "source" => "file:///var/opentripplanner/atlas-feeds/#{s["id"]}.gtfs.zip"
          }
        end)
      )
    end)

    manifest_path = Path.join(otp, "atlas-sources.json")

    previous =
      case File.read(manifest_path) do
        {:ok, json} -> Jason.decode!(json)
        {:error, :enoent} -> []
      end

    previous_ids = Enum.map(previous, & &1["id"])

    update_json(Path.join(otp, "router-config.json"), fn config ->
      other =
        Enum.reject(
          config["updaters"] || [],
          &(&1["type"] == "stop-time-updater" and &1["feedId"] in previous_ids)
        )

      Map.put(config, "updaters", other ++ otp_updaters(sources))
    end)

    atomic_write(
      manifest_path,
      Jason.encode!(
        Enum.map(sources, &Map.take(&1, ~w(id name coverage attribution license license_url))),
        pretty: true
      )
    )

    Atlas.Settings.set("transit_sources_applied", TransitSources.fingerprint(sources))
    File.rm(Path.join(otp, "graph.obj"))
    :ok
  end

  def motis([]), do: "  datasets: {}\n"

  def motis(sources) do
    "  datasets:\n" <>
      Enum.map_join(sources, "", fn s ->
        "    #{s["id"]}:\n      path: \"/input/atlas-feeds/#{s["id"]}.gtfs.zip\"\n" <>
          if realtime?(s) do
            "      rt:\n        - url: #{Jason.encode!(s["realtime_url"])}\n          headers: #{Jason.encode!(TransitSources.headers(s))}\n"
          else
            ""
          end
      end)
  end

  def otp_updaters(sources) do
    for s <- sources,
        realtime?(s),
        do: %{
          "type" => "stop-time-updater",
          "frequency" => "1m",
          "feedId" => s["id"],
          "url" => s["realtime_url"],
          "headers" => TransitSources.headers(s)
        }
  end

  defp realtime?(s), do: s["realtime"] == true and s["realtime_url"] not in [nil, ""]

  defp update_json(path, fun) do
    config =
      case File.read(path) do
        {:ok, json} -> Jason.decode!(json)
        {:error, :enoent} -> %{}
      end

    atomic_write(path, Jason.encode!(fun.(config), pretty: true))
  end

  defp atomic_write(path, body) do
    File.write!(path <> ".next", body)
    File.chmod!(path <> ".next", 0o640)
    File.rename!(path <> ".next", path)
  end
end
