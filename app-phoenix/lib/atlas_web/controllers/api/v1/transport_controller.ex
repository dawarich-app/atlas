defmodule AtlasWeb.Api.V1.TransportController do
  use AtlasWeb.Api.V1.BaseController
  action_fallback AtlasWeb.Api.V1.FallbackController
  alias Atlas.Maps.Transport
  alias AtlasWeb.Schemas
  import OpenApiSpex.Operation, only: [parameter: 5, response: 3]

  plug :require_motis

  @responses %{
    200 => response("MOTIS transport data and metadata", "application/json", Schemas.Response),
    400 => response("Missing parameter", "application/json", Schemas.Error),
    422 => response("Invalid parameter or area too large", "application/json", Schemas.Error),
    501 => response("Requires MOTIS transit backend", "application/json", Schemas.Error),
    502 => response("Upstream error", "application/json", Schemas.Error),
    503 => response("Upstream unavailable", "application/json", Schemas.Error)
  }
  @bbox parameter(
          :bbox,
          :query,
          :string,
          "west,south,east,north; at most 0.04 square degrees and 0.5 degrees per side",
          required: true
        )

  operation(:stops,
    summary: "Transport stops in a local map area",
    parameters: [@bbox],
    responses: @responses
  )

  operation(:lines,
    summary: "Transport service shapes for the next hour (polyline5)",
    parameters: [
      @bbox,
      parameter(:zoom, :query, :integer, "Map zoom 11..18, default 14", required: false)
    ],
    responses: @responses
  )

  operation(:departures,
    summary: "Upcoming departures at the exact stop or platform",
    parameters: [
      parameter(:stop_id, :query, :string, "MOTIS stopId", required: true)
    ],
    responses: @responses
  )

  operation(:trip,
    summary: "Service details with intermediate stops",
    parameters: [
      parameter(:trip_id, :query, :string, "MOTIS tripId", required: true)
    ],
    responses: @responses
  )

  def stops(conn, params) do
    with {:ok, bbox} <- bbox(params["bbox"]), do: respond(conn, Transport.stops(bbox))
  end

  def lines(conn, params) do
    with {:ok, bbox} <- bbox(params["bbox"]),
         {:ok, zoom} <- zoom(params["zoom"]) do
      respond(conn, Transport.lines(bbox, zoom))
    end
  end

  def departures(conn, params) do
    with {:ok, id} <- identifier(params["stop_id"], "stop_id"),
         do: respond(put_resp_header(conn, "cache-control", "no-store"), Transport.departures(id))
  end

  def trip(conn, params) do
    with {:ok, id} <- identifier(params["trip_id"], "trip_id"),
         do: respond(conn, Transport.trip(id))
  end

  defp respond(conn, {:ok, data, extra}), do: json(conn, %{data: data, meta: meta(conn, extra)})
  defp respond(_conn, error), do: error

  defp require_motis(conn, _opts) do
    if Atlas.Settings.transit_backend() == "motis",
      do: conn,
      else:
        conn
        |> error(
          :not_implemented,
          "TRANSPORT_UNSUPPORTED",
          "The transport map API requires the MOTIS transit backend"
        )
        |> halt()
  end

  defp bbox(nil), do: {:error, :missing, "bbox"}

  defp bbox(raw) when is_binary(raw) do
    with [w, s, e, n] <- String.split(raw, ","),
         {w, ""} <- Float.parse(w),
         {s, ""} <- Float.parse(s),
         {e, ""} <- Float.parse(e),
         {n, ""} <- Float.parse(n),
         true <- w >= -180 and e <= 180 and s >= -90 and n <= 90 and w < e and s < n,
         true <- e - w <= 0.5 and n - s <= 0.5 and (e - w) * (n - s) <= 0.04 do
      {:ok, [w, s, e, n]}
    else
      _ -> invalid("bbox", "Zoom in to a valid local map area (west,south,east,north)")
    end
  end

  defp bbox(_), do: invalid("bbox", "bbox must be west,south,east,north")
  defp zoom(nil), do: {:ok, 14}

  defp zoom(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {value, ""} when value in 11..18 -> {:ok, value}
      _ -> invalid("zoom", "zoom must be an integer from 11 to 18")
    end
  end

  defp zoom(_), do: invalid("zoom", "zoom must be an integer from 11 to 18")
  defp identifier(nil, name), do: {:error, :missing, name}
  defp identifier("", name), do: {:error, :missing, name}

  defp identifier(value, _name) when is_binary(value) and byte_size(value) <= 512 do
    if String.match?(value, ~r/[\x00-\x1f\x7f]/),
      do: invalid("id", "invalid transport identifier"),
      else: {:ok, value}
  end

  defp identifier(_, name), do: invalid(name, "transport identifier must be at most 512 bytes")
  defp invalid(param, message), do: {:error, :invalid, message, %{param: param}}
end
