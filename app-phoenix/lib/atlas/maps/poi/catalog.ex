defmodule Atlas.Maps.Poi.Catalog do
  @path Path.expand("../../../../priv/poi_categories.exs", __DIR__)
  @external_resource @path
  @categories Code.eval_file(@path) |> elem(0)

  def all, do: @categories

  def find(key) do
    Enum.find(@categories, fn cat -> cat.key == key end)
  end
end
