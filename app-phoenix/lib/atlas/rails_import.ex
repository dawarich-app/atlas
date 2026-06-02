defmodule Atlas.RailsImport do
  @moduledoc """
  Imports admin/config data from a Rails Atlas SQLite database into the
  Phoenix Repo. Shared by the `mix atlas.migrate_from_rails` task and the
  release entrypoint `Atlas.Release.migrate_from_rails/1`, so it carries no
  Mix dependency.

  Copies rows for `services`, `region_selections` and `settings` (mapping
  Rails `created_at` to Phoenix `inserted_at`), backs the source file up to
  `<source>.pre-phoenix-bak`, and writes a `migrated_from_rails_at` sentinel
  so subsequent runs are no-ops.
  """

  alias Atlas.Control.RegionSelection
  alias Atlas.Control.Service
  alias Atlas.Repo
  alias Atlas.Settings

  @sentinel_key "migrated_from_rails_at"

  def sentinel_key, do: @sentinel_key

  def already_migrated?, do: not is_nil(Settings.get(@sentinel_key))

  @doc """
  Runs the import. Returns:

    * `{:ok, summary}` — counts after a successful copy.
    * `:already_migrated` — sentinel present; nothing changed.
    * `{:error, :source_missing}` — the source SQLite file is absent.
  """
  def run(source_path) do
    cond do
      not File.exists?(source_path) ->
        {:error, :source_missing}

      already_migrated?() ->
        :already_migrated

      true ->
        backup = source_path <> ".pre-phoenix-bak"
        File.cp!(source_path, backup)
        {:ok, migrate_sqlite(source_path, backup)}
    end
  end

  defp migrate_sqlite(source, backup) do
    # Pin one connection: ATTACH is connection-scoped, so the copies must run
    # on the same SQLite handle that ran ATTACH.
    Repo.checkout(fn ->
      Repo.query!("ATTACH DATABASE ? AS rails", [source])

      try do
        copy_services()
        copy_region_selections()
        copy_settings()
      after
        # DETACH is rejected while a transaction is active (e.g. under
        # SQL.Sandbox in tests). Outside a transaction it succeeds; tolerate
        # the error in that case.
        try do
          Repo.query!("DETACH DATABASE rails")
        rescue
          _ -> :ok
        end
      end
    end)

    Settings.set(@sentinel_key, DateTime.utc_now() |> DateTime.to_iso8601())

    %{
      services: Repo.aggregate(Service, :count),
      region_selections: Repo.aggregate(RegionSelection, :count),
      settings: Repo.aggregate(Atlas.Settings.Setting, :count),
      backup: backup
    }
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
