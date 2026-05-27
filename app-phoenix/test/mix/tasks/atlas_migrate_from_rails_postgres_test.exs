defmodule Mix.Tasks.Atlas.MigrateFromRailsPostgresTest do
  use Atlas.DataCase, async: false

  test "raises when Phoenix Repo is not Postgres" do
    # Default test env runs SQLite; the task must detect the adapter mismatch
    # before doing any work and refuse to proceed.
    assert_raise Mix.Error, ~r/not Postgres/, fn ->
      Mix.Tasks.Atlas.MigrateFromRailsPostgres.run(["postgres://localhost/atlas_v1"])
    end
  end

  test "rejects non-postgres URL" do
    assert_raise Mix.Error, ~r/must be a postgres/, fn ->
      Mix.Tasks.Atlas.MigrateFromRailsPostgres.run(["mysql://localhost/atlas"])
    end
  end

  test "raises usage error when called with no arguments" do
    assert_raise Mix.Error, ~r/Usage:/, fn ->
      Mix.Tasks.Atlas.MigrateFromRailsPostgres.run([])
    end
  end

  @tag :postgres
  @tag :skip
  test "smoke test against real Postgres (manual only)" do
    # Run with `DATABASE_URL=postgres://... mix test --only postgres`.
    # Left as documentation; requires a real Postgres source + destination.
    :ok
  end
end
