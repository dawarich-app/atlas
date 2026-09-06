defmodule AtlasWeb.RouteDetails do
  @moduledoc "Choose and describe the same itinerary that is drawn on the map."

  def prepare(%{itineraries: itineraries} = features, mode) do
    sorted = Enum.sort_by(itineraries, &{not transit?(&1), &1[:duration] || 0})
    features |> Map.put(:itineraries, sorted) |> Map.put(:route_mode, mode)
  end

  def prepare(features, mode), do: Map.put(features, :route_mode, mode)

  def legs(%{itineraries: [itinerary | _]}), do: itinerary.legs

  def legs(%{legs: legs, route_mode: mode}) do
    leg_mode = %{"auto" => "CAR", "bicycle" => "BICYCLE", "pedestrian" => "WALK"}[mode]
    Enum.map(legs, &Map.put(&1, :mode, leg_mode))
  end

  def legs(%{legs: legs}), do: legs
  def legs(_), do: []

  def transit?(itinerary) do
    Enum.any?(itinerary.legs, &(&1[:mode] not in [nil, "WALK", "BICYCLE", "CAR"]))
  end

  def itinerary(%{itineraries: [itinerary | _]}), do: itinerary
  def itinerary(_), do: nil

  def label("auto"), do: "Drive"
  def label("bicycle"), do: "Bike"
  def label("pedestrian"), do: "Walk"
  def label("transit"), do: "Public transport"
  def label(mode), do: mode |> to_string() |> String.downcase() |> String.capitalize()

  def minutes(seconds) when is_number(seconds), do: "#{max(1, ceil(seconds / 60))} min"
  def minutes(_), do: ""

  def duration(%{itineraries: [itinerary | _]}), do: minutes(itinerary[:duration])
  def duration(%{summary: summary}), do: minutes(summary["time"])
  def duration(_), do: ""
end
