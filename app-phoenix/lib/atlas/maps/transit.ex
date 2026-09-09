defmodule Atlas.Maps.Transit do
  @moduledoc """
  Transit orchestrator. Calls the selected engine and serializes its response into
  snake_case `plan`/`leg` shapes matching Rails `TransitsController#serialize_plan`.
  """
  alias Atlas.Maps.{Result, Upstream.Client, Upstream.Motis, Upstream.Otp}
  require Logger

  def plan(opts) do
    backend = if Atlas.Settings.transit_backend() == "motis", do: Motis, else: Otp

    case backend.plan(opts) do
      {:ok, body} ->
        plan = serialize_plan(body["plan"] || %{})
        {:ok, %Result{features: plan, upstream_status: "ok"}}

      {:error, %Client.Unavailable{} = e} ->
        Logger.warning("transit unavailable: #{Exception.message(e)}")
        {:error, e}

      {:error, %Client.BadResponse{} = e} ->
        Logger.warning("transit bad response: #{Exception.message(e)}")
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
      shape_format:
        if(get_in(leg, ["legGeometry", "precision"]) == 6,
          do: "google_polyline6",
          else: "google_polyline5"
        )
    }
    |> Map.merge(
      Map.reject(
        %{
          realtime: leg["realTime"],
          cancelled: leg["cancelled"],
          scheduled_start_time: leg["scheduledStartTime"],
          scheduled_end_time: leg["scheduledEndTime"]
        },
        fn {_, value} -> is_nil(value) end
      )
    )
  end

  defp leg_place(nil), do: %{name: nil, lat: nil, lon: nil}

  defp leg_place(place) when is_map(place) do
    %{name: place["name"], lat: place["lat"], lon: place["lon"]}
    |> Map.merge(
      Map.reject(
        %{track: place["track"] || place["platformCode"], stop_id: place["stopId"]},
        fn {_, value} -> is_nil(value) end
      )
    )
  end
end
