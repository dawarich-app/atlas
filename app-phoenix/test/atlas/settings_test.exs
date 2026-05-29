defmodule Atlas.SettingsTest do
  use Atlas.DataCase, async: true
  alias Atlas.Settings

  test "set/get round trip" do
    {:ok, _} = Settings.set("tiles_url", "https://example.com/tiles.json")
    assert Settings.get("tiles_url") == "https://example.com/tiles.json"
  end

  test "get returns default when absent" do
    assert Settings.get("missing", "fallback") == "fallback"
  end

  test "set overwrites existing" do
    Settings.set("key1", "a")
    Settings.set("key1", "b")
    assert Settings.get("key1") == "b"
  end

  test "unset removes" do
    Settings.set("key2", "v")
    Settings.unset("key2")
    assert Settings.get("key2") == nil
  end

  test "accepts atom keys" do
    Settings.set(:atom_key, "x")
    assert Settings.get(:atom_key) == "x"
    assert Settings.get("atom_key") == "x"
  end
end
