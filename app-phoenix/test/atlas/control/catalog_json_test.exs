defmodule Atlas.Control.CatalogJsonTest do
  use ExUnit.Case, async: true
  alias Atlas.Control.CatalogGenerator

  @path Path.join(:code.priv_dir(:atlas), "regions/catalog.json")

  @tag :catalog_artifact
  test "committed catalog.json is present and valid" do
    if File.exists?(@path) do
      entries = @path |> File.read!() |> Jason.decode!()
      assert is_list(entries) and length(entries) > 100
      assert CatalogGenerator.validate(entries) == :ok
      assert Enum.all?(entries, &(&1["kind"] in ~w(continent country subregion city)))
    else
      flunk("catalog.json not generated yet — run `mix atlas.gen_catalog`")
    end
  end
end
