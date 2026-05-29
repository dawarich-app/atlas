defmodule Mix.Tasks.Atlas.MigrateFromRails do
  @moduledoc """
  Migrates data from a Rails Atlas SQLite database into the Phoenix Repo.

  ## Usage

      mix atlas.migrate_from_rails /path/to/rails-atlas.sqlite3

  The task:

    * Backs the source SQLite file up to `<source>.pre-phoenix-bak`.
    * ATTACHes the Rails DB and copies rows for `services`, `region_selections`
      and `settings` into the Phoenix Repo (mapping Rails `created_at` to
      Phoenix `inserted_at`).
    * Uses `ON CONFLICT` to safely upsert services and skip duplicate
      region/setting rows.
    * Writes a sentinel setting `migrated_from_rails_at` so subsequent runs
      are no-ops.
  """

  use Mix.Task

  alias Atlas.Repo
  alias Atlas.Settings
  alias Atlas.Control.RegionSelection
  alias Atlas.Control.Service

  @shortdoc "Migrates data from a Rails Atlas SQLite database into the Phoenix Repo."
  @sentinel_key "migrated_from_rails_at"

  @impl Mix.Task
  def run([source_path]) do
    Mix.Task.run("app.start")
    do_run(source_path)
  end

  def run(_),
    do: Mix.raise("Usage: mix atlas.migrate_from_rails /path/to/rails-atlas.sqlite3")

  defp do_run(source_path) do
    cond do
      not File.exists?(source_path) ->
        Mix.raise("Source file #{source_path} does not exist.")

      already_migrated?() ->
        Mix.shell().info(
          "Already migrated (sentinel #{@sentinel_key} present). Refusing to overwrite."
        )

        :ok

      true ->
        backup = source_path <> ".pre-phoenix-bak"
        File.cp!(source_path, backup)
        Mix.shell().info("Backup written: #{backup}")
        migrate_sqlite(source_path)
    end
  end

  defp already_migrated?, do: not is_nil(Settings.get(@sentinel_key))

  defp migrate_sqlite(source) do
    Repo.query!("ATTACH DATABASE ? AS rails", [source])

    try do
      copy_services()
      copy_region_selections()
      copy_settings()
    after
      # DETACH is not allowed while a transaction is active (e.g. under
      # SQL.Sandbox in tests). In production this is a no-op outside any
      # transaction and succeeds; we tolerate the error in test mode.
      try do
        Repo.query!("DETACH DATABASE rails")
      rescue
        _ -> :ok
      end
    end

    services_count = Repo.aggregate(Service, :count)
    regions_count = Repo.aggregate(RegionSelection, :count)
    settings_count = Repo.aggregate(Atlas.Settings.Setting, :count)

    Settings.set(@sentinel_key, DateTime.utc_now() |> DateTime.to_iso8601())

    Mix.shell().info("""
    Migration complete:
      services: #{services_count}
      region_selections: #{regions_count}
      settings: #{settings_count + 1}  (includes the migrated_from_rails_at sentinel)
    """)
  end

  defp copy_services do
    Repo.query!("""
      INSERT INTO services (
        name, profile, enabled, status, phase, progress, last_log, last_error,
        disk_bytes, last_seen_at,
        auto_update_enabled, update_schedule_cron, dataset_updated_at,
        last_update_check_at, last_update_status, last_update_error, last_update_duration_s,
        pinned_image_tag, inserted_at, updated_at
      )
      SELECT
        name, profile, enabled, status, phase, progress, last_log, last_error,
        disk_bytes, last_seen_at,
        auto_update_enabled, update_schedule_cron, dataset_updated_at,
        last_update_check_at, last_update_status, last_update_error, last_update_duration_s,
        pinned_image_tag, created_at, updated_at
      FROM rails.services
      WHERE TRUE
      ON CONFLICT(name) DO UPDATE SET
        enabled = excluded.enabled,
        auto_update_enabled = excluded.auto_update_enabled,
        update_schedule_cron = excluded.update_schedule_cron,
        pinned_image_tag = excluded.pinned_image_tag
    """)
  end

  defp copy_region_selections do
    Repo.query!("""
      INSERT INTO region_selections (region_name, active, position, orphaned, inserted_at, updated_at)
      SELECT region_name, active, position, orphaned, created_at, updated_at
      FROM rails.region_selections
      WHERE TRUE
      ON CONFLICT(region_name) DO NOTHING
    """)
  end

  defp copy_settings do
    Repo.query!("""
      INSERT INTO settings (key, value, inserted_at, updated_at)
      SELECT key, value, created_at, updated_at
      FROM rails.settings
      WHERE TRUE
      ON CONFLICT(key) DO NOTHING
    """)
  end
end
