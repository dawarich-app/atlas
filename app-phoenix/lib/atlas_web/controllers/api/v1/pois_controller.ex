defmodule AtlasWeb.Api.V1.PoisController do
  use AtlasWeb.Api.V1.BaseController
  alias Atlas.Maps.Poi
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [parameter: 5, response: 3]

  operation(:index,
    summary: "List POIs within a bounding box",
    parameters: [
      parameter(:bbox, :query, :string, "BBox 'w,s,e,n'", required: true),
      parameter(:types, :query, :string, "Comma-separated POI type ids", required: false),
      parameter(:limit, :query, :integer, "Max results (1-1000)", required: false),
      parameter(:lang, :query, :string, "Language code", required: false)
    ],
    responses: %{
      200 => response("POI results", "application/json", Schemas.Response),
      400 => response("Missing bbox", "application/json", Schemas.Error)
    }
  )

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
        missing_param(conn, "bbox")
    end
  end

  operation(:categories,
    summary: "List the POI category catalog",
    responses: %{
      200 => response("POI category catalog", "application/json", Schemas.Response)
    }
  )

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
