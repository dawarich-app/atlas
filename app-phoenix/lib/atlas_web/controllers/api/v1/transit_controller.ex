defmodule AtlasWeb.Api.V1.TransitController do
  use AtlasWeb.Api.V1.BaseController
  action_fallback AtlasWeb.Api.V1.FallbackController

  alias Atlas.Maps.Transit
  alias Atlas.Maps.Upstream.Otp
  alias AtlasWeb.Schemas

  import OpenApiSpex.Operation, only: [parameter: 5, response: 3]

  operation(:show,
    summary: "Plan a transit trip between two coordinates",
    parameters: [
      parameter(:from, :query, :string, "Origin 'lat,lon'", required: true),
      parameter(:to, :query, :string, "Destination 'lat,lon'", required: true),
      parameter(:time, :query, :string, "ISO 8601 timestamp (defaults to now)", required: false),
      parameter(:modes, :query, :string, "Comma-separated modes (default TRANSIT,WALK)", required: false),
      parameter(:num, :query, :integer, "Number of itineraries (1..6, default 3)", required: false),
      parameter(:arrive_by, :query, :string, "Arrive-by flag", required: false)
    ],
    responses: %{
      200 => response("Transit result", "application/json", Schemas.Response),
      400 => response("Missing parameter", "application/json", Schemas.Error),
      422 => response("Invalid parameter", "application/json", Schemas.Error),
      502 => response("Upstream error", "application/json", Schemas.Error),
      503 => response("Upstream unavailable", "application/json", Schemas.Error)
    }
  )

  def show(conn, params) do
    with {:ok, from} <- parse_endpoint(params["from"], "from"),
         {:ok, to} <- parse_endpoint(params["to"], "to") do
      {iso, date, time} = parse_time(params["time"])
      modes = (params["modes"] || Otp.default_modes()) |> to_string()
      num = clamp_int(params["num"], 3, 1, 6)

      with {:ok, result} <-
             Transit.plan(
               from: from,
               to: to,
               date: date,
               time: time,
               modes: modes,
               num: num,
               arrive_by: params["arrive_by"]
             ) do
        json(conn, %{
          data: result.features,
          meta:
            meta(conn, %{
              upstream: result.upstream_status,
              time: iso,
              modes: modes,
              num: num
            })
        })
      end
    end
  end

  defp parse_endpoint(nil, name), do: {:error, :missing, name}
  defp parse_endpoint("", name), do: {:error, :missing, name}

  defp parse_endpoint(raw, name) do
    case parse_latlon(raw) do
      {:ok, coord} -> {:ok, coord}
      :error -> {:error, :invalid, "#{name} must be 'lat,lon'", %{param: name}}
    end
  end

  # ISO8601 → {iso_string, "YYYY-MM-DD", "HH:MM"}; default to now on parse failure.
  defp parse_time(raw) do
    case DateTime.from_iso8601(raw || "") do
      {:ok, dt, _} ->
        {DateTime.to_iso8601(dt), Date.to_iso8601(DateTime.to_date(dt)), Time.to_iso8601(DateTime.to_time(dt))}

      _ ->
        now = DateTime.utc_now()
        {DateTime.to_iso8601(now), Date.to_iso8601(DateTime.to_date(now)), Time.to_iso8601(DateTime.to_time(now))}
    end
  end
end
