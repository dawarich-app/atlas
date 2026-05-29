defmodule Mix.Tasks.Atlas.MigrateFromRailsTest do
  use Atlas.DataCase, async: false

  import ExUnit.CaptureIO

  alias Atlas.Repo
  alias Atlas.Settings
  alias Atlas.Control.RegionSelection
  alias Atlas.Control.Service

  @sentinel_key "migrated_from_rails_at"

  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("atlas-migrate-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    source = Path.join(tmp_dir, "rails-atlas.sqlite3")

    on_exit(fn -> File.rm_rf(tmp_dir) end)

    %{tmp_dir: tmp_dir, source: source}
  end

  describe "first run" do
    test "copies services, region_selections and settings; writes sentinel; writes backup",
         %{source: source} do
      build_rails_db(source)

      capture_io(fn ->
        Mix.Tasks.Atlas.MigrateFromRails.run([source])
      end)

      assert Repo.aggregate(Service, :count) == 2
      assert Repo.aggregate(RegionSelection, :count) == 2

      assert Settings.get("tiles_url") == "https://tiles.example.com/style.json"
      assert Settings.get(@sentinel_key) != nil

      assert File.exists?(source <> ".pre-phoenix-bak")
    end

    test "imports service rows with correct status and timestamps", %{source: source} do
      build_rails_db(source)

      capture_io(fn ->
        Mix.Tasks.Atlas.MigrateFromRails.run([source])
      end)

      photon = Repo.get_by(Service, name: "photon")
      assert photon.profile == "geocoder"
      assert photon.enabled == true
      assert photon.status == :ready
      assert %DateTime{} = photon.inserted_at
    end
  end

  describe "idempotency" do
    test "second run with sentinel present is a no-op", %{source: source} do
      build_rails_db(source)

      capture_io(fn -> Mix.Tasks.Atlas.MigrateFromRails.run([source]) end)
      first_count = Repo.aggregate(Service, :count)

      output =
        capture_io(fn -> Mix.Tasks.Atlas.MigrateFromRails.run([source]) end)

      assert output =~ "Already migrated"
      assert Repo.aggregate(Service, :count) == first_count
    end
  end

  describe "failure modes" do
    test "raises when source file does not exist" do
      assert_raise Mix.Error, ~r/does not exist/, fn ->
        Mix.Tasks.Atlas.MigrateFromRails.run(["/nonexistent/path/atlas.sqlite3"])
      end
    end

    test "raises when called without arguments" do
      assert_raise Mix.Error, ~r/Usage:/, fn ->
        Mix.Tasks.Atlas.MigrateFromRails.run([])
      end
    end
  end

  # Build a minimal Rails-shaped SQLite database with the columns the migration
  # task reads. Rails uses `created_at` instead of Phoenix's `inserted_at`.
  defp build_rails_db(path) do
    {:ok, conn} = Exqlite.Sqlite3.open(path)

    Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE services (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      profile TEXT NOT NULL,
      enabled BOOLEAN NOT NULL DEFAULT 0,
      status INTEGER NOT NULL DEFAULT 0,
      phase TEXT,
      progress REAL,
      last_log TEXT,
      last_error TEXT,
      disk_bytes BIGINT NOT NULL DEFAULT 0,
      last_seen_at DATETIME,
      auto_update_enabled BOOLEAN NOT NULL DEFAULT 0,
      update_schedule_cron TEXT,
      dataset_updated_at DATETIME,
      last_update_check_at DATETIME,
      last_update_status TEXT,
      last_update_error TEXT,
      last_update_duration_s INTEGER,
      pinned_image_tag TEXT,
      created_at DATETIME NOT NULL,
      updated_at DATETIME NOT NULL
    );
    """)

    Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE region_selections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      region_name TEXT NOT NULL UNIQUE,
      active BOOLEAN NOT NULL DEFAULT 1,
      position INTEGER NOT NULL DEFAULT 0,
      orphaned BOOLEAN NOT NULL DEFAULT 0,
      created_at DATETIME NOT NULL,
      updated_at DATETIME NOT NULL
    );
    """)

    Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      key TEXT UNIQUE,
      value TEXT,
      created_at DATETIME NOT NULL,
      updated_at DATETIME NOT NULL
    );
    """)

    now = "2026-05-01 12:00:00"

    Exqlite.Sqlite3.execute(conn, """
    INSERT INTO services (name, profile, enabled, status, disk_bytes,
      auto_update_enabled, created_at, updated_at)
    VALUES
      ('photon', 'geocoder', 1, 5, 1024, 1, '#{now}', '#{now}'),
      ('valhalla', 'router', 0, 1, 0, 0, '#{now}', '#{now}');
    """)

    Exqlite.Sqlite3.execute(conn, """
    INSERT INTO region_selections (region_name, active, position, orphaned, created_at, updated_at)
    VALUES
      ('europe/germany', 1, 0, 0, '#{now}', '#{now}'),
      ('europe/france', 1, 1, 0, '#{now}', '#{now}');
    """)

    Exqlite.Sqlite3.execute(conn, """
    INSERT INTO settings (key, value, created_at, updated_at)
    VALUES
      ('tiles_url', 'https://tiles.example.com/style.json', '#{now}', '#{now}');
    """)

    Exqlite.Sqlite3.close(conn)
    :ok
  end
end
