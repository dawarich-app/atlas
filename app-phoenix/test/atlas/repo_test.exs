defmodule Atlas.RepoTest do
  use ExUnit.Case, async: false

  test "selects SQLite adapter when DATABASE_URL is unset" do
    System.delete_env("DATABASE_URL")
    assert Atlas.Repo.adapter() == Ecto.Adapters.SQLite3
  end

  test "selects Postgres adapter when DATABASE_URL starts with postgres://" do
    System.put_env("DATABASE_URL", "postgres://localhost/atlas")
    assert Atlas.Repo.adapter() == Ecto.Adapters.Postgres
  after
    System.delete_env("DATABASE_URL")
  end

  test "selects Postgres adapter when DATABASE_URL starts with postgresql://" do
    System.put_env("DATABASE_URL", "postgresql://localhost/atlas")
    assert Atlas.Repo.adapter() == Ecto.Adapters.Postgres
  after
    System.delete_env("DATABASE_URL")
  end
end
