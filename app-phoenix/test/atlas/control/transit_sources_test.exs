defmodule Atlas.Control.TransitSourcesTest do
  use Atlas.DataCase, async: false
  alias Atlas.Control.{TransitSourceFiles, TransitSources}

  setup do
    dir = Path.join(System.tmp_dir!(), "transit-sources-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "catalog connection is explicit and duplicate URLs are rejected" do
    refute TransitSources.configured?()
    assert :ok = TransitSources.connect("vbb")
    assert [%{"id" => "vbb", "enabled" => true}] = TransitSources.enabled()

    assert {:error, _} =
             TransitSources.add(%{
               "name" => "Same feed",
               "url" => hd(TransitSources.catalog())["url"]
             })

    assert :ok = TransitSources.toggle("vbb", "enabled")
    assert [] = TransitSources.enabled()
  end

  test "custom sources validate URLs and headers without executing downloads" do
    assert {:error, _} = TransitSources.add(%{"name" => "Invalid", "url" => "file:///etc/passwd"})

    assert {:error, _} =
             TransitSources.add(%{
               "name" => "Invalid",
               "url" => "https://user:pass@example.test/feed.zip"
             })

    assert {:error, _} =
             TransitSources.add(%{
               "name" => "Invalid",
               "url" => "https://example.test/feed.zip",
               "header_name" => "bad\nheader"
             })

    assert :ok = TransitSources.add(%{"name" => "City", "url" => "https://example.test/feed.zip"})
    assert [%{"realtime" => false, "id" => id}] = TransitSources.enabled()
    assert String.starts_with?(id, "custom-")
  end

  test "failed or invalid downloads keep last validated file and record a warning", %{dir: dir} do
    s = hd(TransitSources.catalog()) |> Map.merge(%{"enabled" => true, "realtime" => true})

    good = fn _, path, _ ->
      files =
        for name <- ~w(agency.txt stops.txt routes.txt trips.txt stop_times.txt calendar.txt),
            do: {String.to_charlist(name), "header\nvalue\n"}

      :zip.create(String.to_charlist(path), files)
    end

    assert [^s] = TransitSourceFiles.prepare([s], dir, fn _ -> :ok end, good)
    path = Path.join(dir, "gtfs/atlas-feeds/" <> TransitSourceFiles.cache_name(s))
    original = File.read!(path)
    timestamp = TransitSources.statuses()["vbb"]["downloaded_at"]

    bad = fn _, dest, _ ->
      File.write!(dest, "<html>Error</html>")
      {:ok, dest}
    end

    assert [^s] = TransitSourceFiles.prepare([s], dir, fn _ -> :ok end, bad)
    assert File.read!(path) == original
    assert TransitSources.statuses()["vbb"]["downloaded_at"] == timestamp
    assert TransitSources.statuses()["vbb"]["error"] =~ "last valid"
    refute File.exists?(path <> ".next")
  end

  test "new source with failed download is not staged", %{dir: dir} do
    s = hd(TransitSources.catalog())

    assert [] =
             TransitSourceFiles.prepare([s], dir, fn _ -> :ok end, fn _, _, _ ->
               {:error, :timeout}
             end)

    refute TransitSources.statuses()["vbb"]["downloaded_at"]
  end

  test "changing a URL never falls back to a different source's cached file", %{dir: dir} do
    source = hd(TransitSources.catalog())
    File.mkdir_p!(Path.join(dir, "gtfs/atlas-feeds"))

    File.write!(
      Path.join(dir, "gtfs/atlas-feeds/" <> TransitSourceFiles.cache_name(source)),
      "old provider"
    )

    changed = Map.put(source, "url", "https://example.test/new.zip")

    assert [] =
             TransitSourceFiles.prepare([changed], dir, fn _ -> :ok end, fn _, _, _ ->
               {:error, :timeout}
             end)
  end

  test "wizard reports disabled coverage without blocking setup" do
    assert :ok = TransitSources.connect("vbb")
    draft = %{"capabilities" => ["transit"], "regions" => ["berlin"], "backend" => "motis"}
    catalog = [Atlas.Control.RegionCatalog.find("berlin")]
    assert Atlas.Control.Onboarding.missing_transit_regions(draft, catalog) == []
    assert :ok = TransitSources.toggle("vbb", "enabled")
    assert [%{name: "berlin"}] = Atlas.Control.Onboarding.missing_transit_regions(draft, catalog)
    assert :ok = Atlas.Control.Onboarding.validate(draft, catalog)
  end

  test "editing keeps source ID and secret, and explicitly clears the key" do
    assert :ok =
             TransitSources.add(%{
               "name" => "City",
               "url" => "https://example.test/feed.zip",
               "header_name" => "Authorization",
               "header_value" => "secret"
             })

    [source] = TransitSources.all()
    id = source["id"]
    assert :ok = TransitSources.update(id, %{"name" => "New label", "header_value" => ""})

    assert [%{"id" => ^id, "name" => "New label", "header_value" => "secret"}] =
             TransitSources.all()

    assert :ok = TransitSources.update(id, %{"clear_key" => "true"})
    assert [%{"header_value" => ""}] = TransitSources.all()
  end

  test "MOTIS and OTP share deterministic feed IDs and realtime can be disabled", %{dir: dir} do
    s =
      hd(TransitSources.catalog())
      |> Map.merge(%{
        "realtime" => true,
        "header_name" => "Authorization",
        "header_value" => "Bearer test"
      })

    assert TransitSourceFiles.motis([s]) =~ "    vbb:"
    assert TransitSourceFiles.motis([s]) =~ "Bearer test"

    assert [%{"feedId" => "vbb", "headers" => %{"Authorization" => "Bearer test"}}] =
             TransitSourceFiles.otp_updaters([s])

    assert [] = TransitSourceFiles.otp_updaters([Map.put(s, "realtime", false)])
    refute TransitSourceFiles.motis([Map.put(s, "realtime", false)]) =~ "rt:"
    File.mkdir_p!(Path.join(dir, "gtfs/atlas-feeds"))

    File.write!(
      Path.join(dir, "gtfs/atlas-feeds/" <> TransitSourceFiles.cache_name(s)),
      "validated"
    )

    File.mkdir_p!(Path.join(dir, "otp"))

    File.write!(
      Path.join(dir, "otp/build-config.json"),
      ~s({"osmDefaults":{"timeZone":"Europe/Berlin"}})
    )

    File.write!(
      Path.join(dir, "otp/router-config.json"),
      ~s({"updaters":[{"type":"vehicle-positions","feedId":"other"}]})
    )

    assert :ok = TransitSourceFiles.stage([s], dir)
    build = File.read!(Path.join(dir, "otp/build-config.json")) |> Jason.decode!()
    assert build["osmDefaults"]["timeZone"] == "Europe/Berlin"
    assert [%{"feedId" => "vbb", "type" => "gtfs"}] = build["transitFeeds"]
    assert :ok = TransitSourceFiles.stage([], dir)
    router = File.read!(Path.join(dir, "otp/router-config.json")) |> Jason.decode!()
    assert [%{"feedId" => "other"}] = router["updaters"]
    assert File.read!(Path.join(dir, "otp/motis-datasets.yml")) == "  datasets: {}\n"
  end
end
