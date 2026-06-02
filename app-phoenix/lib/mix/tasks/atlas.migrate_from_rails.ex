defmodule Mix.Tasks.Atlas.MigrateFromRails do
  @moduledoc """
  Migrates data from a Rails Atlas SQLite database into the Phoenix Repo.

  ## Usage

      mix atlas.migrate_from_rails /path/to/rails-atlas.sqlite3

  Delegates to `Atlas.RailsImport`: backs the source up to
  `<source>.pre-phoenix-bak`, copies `services`, `region_selections` and
  `settings`, and writes a `migrated_from_rails_at` sentinel so subsequent
  runs are no-ops. For production releases use
  `Atlas.Release.migrate_from_rails/1` instead.
  """

  use Mix.Task

  @shortdoc "Migrates data from a Rails Atlas SQLite database into the Phoenix Repo."

  @impl Mix.Task
  def run([source_path]) do
    Mix.Task.run("app.start")

    case Atlas.RailsImport.run(source_path) do
      {:error, :source_missing} ->
        Mix.raise("Source file #{source_path} does not exist.")

      :already_migrated ->
        Mix.shell().info(
          "Already migrated (sentinel #{Atlas.RailsImport.sentinel_key()} present). Refusing to overwrite."
        )

      {:ok, summary} ->
        Mix.shell().info("Backup written: #{summary.backup}")

        Mix.shell().info("""
        Migration complete:
          services: #{summary.services}
          region_selections: #{summary.region_selections}
          settings: #{summary.settings}  (includes the migrated_from_rails_at sentinel)
        """)
    end
  end

  def run(_),
    do: Mix.raise("Usage: mix atlas.migrate_from_rails /path/to/rails-atlas.sqlite3")
end
