defmodule Atlas.VersionTest do
  use ExUnit.Case, async: false

  alias Atlas.Version

  test "version/0 reads the canonical mix.exs version" do
    assert Version.version() == Mix.Project.config()[:version]
  end

  test "revision/0 is the build-time git SHA when baked in" do
    System.put_env("APP_REVISION", "abc1234def")
    on_exit(fn -> System.delete_env("APP_REVISION") end)

    assert Version.revision() == "abc1234"
  end

  test "revision/0 is nil outside a release build" do
    System.delete_env("APP_REVISION")
    assert Version.revision() == nil
  end

  test "display/0 combines version and revision" do
    System.put_env("APP_REVISION", "abc1234def")
    on_exit(fn -> System.delete_env("APP_REVISION") end)

    assert Version.display() == "v#{Version.version()} (abc1234)"
  end

  test "display/0 without a revision is just the version" do
    System.delete_env("APP_REVISION")
    assert Version.display() == "v#{Version.version()}"
  end
end
