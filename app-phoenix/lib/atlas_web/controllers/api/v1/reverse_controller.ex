defmodule AtlasWeb.Api.V1.ReverseController do
  use AtlasWeb.Api.V1.BaseController
  alias Atlas.Maps.Reverse
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [parameter: 5, response: 3]

  operation(:show,
    summary: "Reverse-geocode a single coordinate",
    parameters: [
      parameter(:lat, :query, :number, "Latitude", required: true),
      parameter(:lon, :query, :number, "Longitude", required: true),
      parameter(:lang, :query, :string, "Language code", required: false)
    ],
    responses: %{
      200 => response("Reverse result", "application/json", Schemas.Response),
      400 => response("Missing parameter", "application/json", Schemas.Error)
    }
  )

  def show(conn, params) do
    with {:ok, lat_raw} <- require_param(conn, "lat"),
         {:ok, lon_raw} <- require_param(conn, "lon"),
         lat when not is_nil(lat) <- parse_float(lat_raw),
         lon when not is_nil(lon) <- parse_float(lon_raw) do
      result = Reverse.lookup(lat: lat, lon: lon, lang: params["lang"])

      json(conn, %{
        data: result.features,
        meta: meta(conn, %{upstream: result.upstream_status})
      })
    else
      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "MISSING_PARAM", message: "lat and lon required"}})
    end
  end

  operation(:batch,
    summary: "Reverse-geocode a batch of coordinates",
    request_body:
      {"Batch request", "application/json",
       %OpenApiSpex.Schema{type: :object, properties: %{coords: %OpenApiSpex.Schema{type: :array}}}},
    responses: %{
      200 => response("Batch reverse results", "application/json", Schemas.Response),
      400 => response("Missing coords", "application/json", Schemas.Error)
    }
  )

  def batch(conn, %{"coords" => coords} = params) when is_list(coords) do
    case normalize_coords(coords) do
      {:ok, normalized} ->
        result = Reverse.batch(%{coords: normalized, lang: params["lang"]})

        json(conn, %{
          data: result.results,
          meta:
            meta(conn, %{
              count: length(result.results),
              cache_hits: result.cache_hits,
              cache_misses: result.cache_misses,
              upstream_errors: result.upstream_errors,
              grid_precision: Reverse.grid_decimals(),
              max_coords: Reverse.max_coords()
            })
        })

      {:error, idx} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: %{
            code: "INVALID_COORD",
            message: "coord at index #{idx} is missing lat/lon or has invalid values"
          }
        })
    end
  end

  def batch(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "MISSING_PARAM", param: "coords", message: "coords array required"}})
  end

  defp normalize_coords(coords) do
    coords
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {coord, idx}, {:ok, acc} ->
      case coord do
        %{"lat" => lat, "lon" => lon} when is_number(lat) and is_number(lon) ->
          {:cont, {:ok, [%{lat: lat * 1.0, lon: lon * 1.0} | acc]}}

        _ ->
          {:halt, {:error, idx}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end
end
