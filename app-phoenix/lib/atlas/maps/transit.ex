defmodule Atlas.Maps.Transit do
  @moduledoc """
  Transit orchestrator. Calls OTP and serializes the camelCase response into
  snake_case `plan`/`leg` shapes matching Rails `TransitsController#serialize_plan`.
  """
  alias Atlas.Maps.{Result, Upstream.Otp, Upstream.Client}
  require Logger

  def plan(opts) do
    case Otp.plan(opts) do
      {:ok, body} ->
        plan = serialize_plan(body["plan"] || %{})
        {:ok, %Result{features: plan, upstream_status: "ok"}}

      {:error, %Client.Unavailable{} = e} ->
        Logger.warning("otp unavailable: #{Exception.message(e)}")
        {:error, e}

      {:error, %Client.BadResponse{} = e} ->
        Logger.warning("otp bad response: #{Exception.message(e)}")
        {:error, e}
    end
  end

  @doc false
  def serialize_plan(plan) when is_map(plan) do
    %{
      from: plan["from"],
      to: plan["to"],
      itineraries:
        (plan["itineraries"] || [])
        |> Enum.map(fn it ->
          %{
            start_time: it["startTime"],
            end_time: it["endTime"],
            duration: it["duration"],
            walk_distance: it["walkDistance"],
            transfers: it["transfers"],
            legs: (it["legs"] || []) |> Enum.map(&serialize_leg/1)
          }
        end)
    }
  end

  def serialize_plan(_), do: %{from: nil, to: nil, itineraries: []}

  @doc false
  def serialize_leg(leg) when is_map(leg) do
    %{
      mode: leg["mode"],
      route_name: leg["routeShortName"] || leg["route"],
      headsign: leg["headsign"],
      agency_name: leg["agencyName"],
      start_time: leg["startTime"],
      end_time: leg["endTime"],
      duration: leg["duration"],
      distance: leg["distance"],
      from: leg_place(leg["from"]),
      to: leg_place(leg["to"]),
      shape: get_in(leg, ["legGeometry", "points"]),
      shape_format: "google_polyline5"
    }
  end

  defp leg_place(nil), do: %{name: nil, lat: nil, lon: nil}

  defp leg_place(place) when is_map(place) do
    %{name: place["name"], lat: place["lat"], lon: place["lon"]}
  end
end
