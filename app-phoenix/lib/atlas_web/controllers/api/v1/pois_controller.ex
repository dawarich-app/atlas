defmodule AtlasWeb.Api.V1.PoisController do
  use AtlasWeb.Api.V1.BaseController
  action_fallback AtlasWeb.Api.V1.FallbackController

  alias Atlas.Maps.Poi
  alias Atlas.Maps.Poi.Catalog
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [parameter: 5, response: 3]

  operation(:index,
    summary: "List POIs within a bounding box",
    parameters: [
      parameter(:bbox, :query, :string, "BBox 's,w,n,e' (south,west,north,east)", required: true),
      parameter(:types, :query, :string, "Comma-separated POI type ids", required: false),
      parameter(:q, :query, :string, "Free-text query (uses Photon when present)", required: false),
      parameter(:limit, :query, :integer, "Max results (1-1000)", required: false),
      parameter(:lang, :query, :string, "Language code", required: false)
    ],
    responses: %{
      200 => response("POI results", "application/json", Schemas.Response),
      400 => response("Missing bbox", "application/json", Schemas.Error),
      422 => response("Invalid bbox or types", "application/json", Schemas.Error)
    }
  )

  def index(conn, params) do
    with {:ok, bbox} <- require_bbox(params["bbox"]),
         {:ok, types} <- resolve_types(params["types"]) do
      limit = clamp_int(params["limit"], 300, 1, 1000)
      query = (params["q"] || "") |> to_string() |> String.trim()

      with {:ok, result} <- run_search(query, bbox, types, limit, params["lang"]) do
        json(conn, %{
          data: %{features: result.features},
          meta:
            meta(conn, %{
              types: types,
              bbox: bbox,
              q: if(query == "", do: nil, else: query),
              upstream: result.upstream_status,
              count: length(result.features)
            })
        })
      end
    end
  end

  defp run_search("", bbox, types, limit, lang) do
    Poi.nearby(bbox: bbox, types: types, limit: limit, lang: lang)
  end

  defp run_search(query, bbox, types, limit, lang) do
    Poi.search_within_categories(bbox: bbox, types: types, limit: limit, lang: lang, query: query)
  end

  defp require_bbox(nil), do: {:error, :missing, "bbox"}
  defp require_bbox(""), do: {:error, :missing, "bbox"}

  defp require_bbox(raw) when is_binary(raw) do
    case parse_bbox(raw) do
      [_, _, _, _] = bbox -> {:ok, bbox}
      _ -> {:error, :invalid, "bbox must be 's,w,n,e'", %{param: "bbox"}}
    end
  end

  # Rails contract:
  #   1. Empty types → default to first 2 pinned items from Catalog
  #   2. If selectors_for(types) == [] (all unknown), 422
  defp resolve_types(raw) do
    types = parse_types(raw)
    types = if types == [], do: default_types(), else: types

    if Catalog.selectors_for(types) == [] do
      {:error, :invalid, "no recognised types", %{types: types}}
    else
      {:ok, types}
    end
  end

  defp default_types do
    Catalog.pinned()
    |> Enum.take(2)
    |> Enum.map(& &1.id)
  end

  operation(:categories,
    summary: "List the POI category catalog",
    responses: %{
      200 => response("POI category catalog", "application/json", Schemas.Response)
    }
  )

  def categories(conn, _params) do
    sections = Catalog.sections() |> Enum.map(&serialize_section/1)
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
      icon_svg: Catalog.icon_svg(section.icon),
      items:
        Enum.map(section.items, fn item ->
          %{
            id: item.id,
            label: item.label,
            icon: item.icon,
            icon_svg: Catalog.icon_svg(item.icon),
            pinned: item.pinned
          }
        end)
    }
  end
end
