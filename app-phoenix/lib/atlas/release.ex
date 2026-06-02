defmodule Atlas.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :atlas

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Imports admin/config data from a Rails Atlas SQLite database into the
  Phoenix Repo. Run once during the Rails → Phoenix upgrade:

      bin/atlas eval 'Atlas.Release.migrate_from_rails("/data/app.sqlite3")'

  Ensures the Phoenix schema exists, then delegates to `Atlas.RailsImport`
  (idempotent via its sentinel). Halts non-zero if the source is missing.
  """
  def migrate_from_rails(source_path) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Atlas.Repo, fn repo ->
        Ecto.Migrator.run(repo, :up, all: true)

        case Atlas.RailsImport.run(source_path) do
          {:ok, summary} ->
            IO.puts(
              "Rails import complete: services=#{summary.services} " <>
                "region_selections=#{summary.region_selections} settings=#{summary.settings} " <>
                "(backup: #{summary.backup})"
            )

          :already_migrated ->
            IO.puts("Rails import already applied (sentinel present); nothing to do.")

          {:error, :source_missing} ->
            IO.puts(:stderr, "Source file #{source_path} does not exist.")
            System.halt(1)
        end
      end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
