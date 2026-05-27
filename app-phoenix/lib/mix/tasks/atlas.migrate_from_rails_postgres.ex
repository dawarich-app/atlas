defmodule Mix.Tasks.Atlas.MigrateFromRailsPostgres do
  @moduledoc """
  Migrates data from a Rails Atlas Postgres database into the Phoenix Repo
  (when Phoenix is configured to use Postgres).

  ## Usage

      mix atlas.migrate_from_rails_postgres postgres://user:pw@host:5432/atlas_v1

  The task shells out to `pg_dump` + `psql`:

    * `pg_dump --data-only` against the source URL, dumping only the
      `services`, `region_selections` and `settings` tables.
    * `psql --single-transaction` applies the dump to the destination URL
      configured on `Atlas.Repo`.
    * Writes a sentinel setting `migrated_from_rails_at` for idempotency.

  The task aborts when the Phoenix Repo is not using the Postgres adapter
  (in which case `mix atlas.migrate_from_rails` is the correct entry point).
  """

  use Mix.Task

  alias Atlas.Settings

  @shortdoc "Migrates from a Rails Atlas Postgres database into the Phoenix Repo (Postgres)."
  @sentinel_key "migrated_from_rails_at"

  @impl Mix.Task
  def run([source_url]) do
    Mix.Task.run("app.start")
    do_run(source_url)
  end

  def run(_),
    do:
      Mix.raise(
        "Usage: mix atlas.migrate_from_rails_postgres postgres://user:pw@host:5432/atlas_v1"
      )

  defp do_run(source_url) do
    cond do
      not is_binary(source_url) or
          not String.starts_with?(source_url, ["postgres://", "postgresql://"]) ->
        Mix.raise("Source must be a postgres:// or postgresql:// URL")

      not postgres_repo?() ->
        Mix.raise(
          "Phoenix Repo is not Postgres. Use mix atlas.migrate_from_rails for SQLite."
        )

      already_migrated?() ->
        Mix.shell().info("Already migrated. Refusing to overwrite.")
        :ok

      true ->
        migrate_postgres(source_url)
    end
  end

  defp already_migrated?, do: not is_nil(Settings.get(@sentinel_key))

  defp postgres_repo? do
    # `Atlas.Repo.__adapter__/0` is resolved at compile time via
    # `Application.compile_env`, so we call it through `apply/3` to keep this
    # check truly runtime — otherwise the compiler flags the comparison as
    # always-false in a SQLite build.
    apply(Atlas.Repo, :__adapter__, []) == Ecto.Adapters.Postgres
  end

  defp migrate_postgres(source_url) do
    dump_path =
      Path.join(System.tmp_dir!(), "atlas_rails_dump_#{:os.system_time(:second)}.sql")

    case System.cmd(
           "pg_dump",
           [
             "--data-only",
             "--no-owner",
             "--table=services",
             "--table=region_selections",
             "--table=settings",
             "--file=#{dump_path}",
             source_url
           ],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        Mix.shell().info("Dump written: #{dump_path}")
        if output != "", do: Mix.shell().info(output)

      {error_output, code} ->
        Mix.raise("pg_dump failed (exit #{code}): #{error_output}")
    end

    dest_url =
      Atlas.Repo.config()[:url] ||
        Mix.raise("Phoenix Repo has no :url configured for Postgres")

    case System.cmd(
           "psql",
           ["--single-transaction", dest_url, "-f", dump_path],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {error_output, code} ->
        Mix.raise("psql restore failed (exit #{code}): #{error_output}")
    end

    Settings.set(@sentinel_key, DateTime.utc_now() |> DateTime.to_iso8601())
    Mix.shell().info("Migration complete.")
  end
end
