defmodule AtlasWeb.Api.V1.PoisController do
  use AtlasWeb.Api.V1.BaseController
  alias Atlas.Maps.Poi

  def index(conn, params) do
    case parse_bbox(params["bbox"]) do
      [_, _, _, _] = bbox ->
        types = parse_types(params["types"])
        limit = clamp_int(params["limit"], 300, 1, 1000)
        result = Poi.nearby(bbox: bbox, types: types, limit: limit, lang: params["lang"])

        json(conn, %{
          data: %{features: result.features},
          meta:
            meta(conn, %{
              types: types,
              bbox: bbox,
              q: nil,
              upstream: result.upstream_status,
              count: length(result.features)
            })
        })

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "MISSING_PARAM", message: "bbox required as 'w,s,e,n'"}})
    end
  end

  def categories(conn, _params) do
    sections = Atlas.Maps.Poi.Catalog.sections() |> Enum.map(&serialize_section/1)
    json(conn, %{data: %{sections: sections}})
  end

  defp parse_types(nil), do: []

  defp parse_types(str) when is_binary(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_types(list) when is_list(list), do: list

  defp serialize_section(section) do
    %{
      id: section.id,
      label: section.label,
      icon: section.icon,
      items:
        Enum.map(section.items, fn item ->
          %{id: item.id, label: item.label, icon: item.icon, pinned: item.pinned}
        end)
    }
  end
end
