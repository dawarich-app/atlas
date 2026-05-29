defmodule Atlas.RepoTest do
  use ExUnit.Case, async: false

  test "adapter/0 returns the compile-time adapter (SQLite3 in test env)" do
    assert Atlas.Repo.adapter() == Ecto.Adapters.SQLite3
  end
end
