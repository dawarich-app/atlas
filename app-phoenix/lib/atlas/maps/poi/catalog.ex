defmodule Atlas.Maps.Poi.Catalog do
  @path Path.expand("../../../../priv/poi_categories.exs", __DIR__)
  @external_resource @path
  @sections Code.eval_file(@path) |> elem(0)

  def sections, do: @sections

  def find_item(id) when is_binary(id) do
    Enum.find_value(@sections, fn section ->
      case Enum.find(section.items, &(&1.id == id)) do
        nil -> nil
        item -> Map.put(item, :section_id, section.id)
      end
    end)
  end

  def find_item(_), do: nil

  def selectors_for(ids) when is_list(ids) do
    ids
    |> Enum.map(&find_item/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.selector)
  end

  def section_for_item(id) do
    case find_item(id) do
      nil -> nil
      item -> item.section_id
    end
  end

  def pinned do
    @sections
    |> Enum.flat_map(& &1.items)
    |> Enum.filter(& &1.pinned)
  end
end
