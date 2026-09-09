defmodule AtlasWeb.RouteDetails do
  @moduledoc "Choose and describe the same itinerary that is drawn on the map."

  def prepare(%{itineraries: itineraries} = features, mode) do
    sorted = Enum.sort_by(itineraries, &{not transit?(&1), &1[:duration] || 0})
    features |> Map.put(:itineraries, sorted) |> Map.put(:route_mode, mode)
  end

  def prepare(features, mode), do: Map.put(features, :route_mode, mode)

  def legs(%{itineraries: [itinerary | _]}), do: styled_legs(itinerary.legs)

  def legs(%{legs: legs, route_mode: mode}) do
    leg_mode = %{"auto" => "CAR", "bicycle" => "BICYCLE", "pedestrian" => "WALK"}[mode]
    legs |> Enum.map(&Map.put(&1, :mode, leg_mode)) |> styled_legs()
  end

  def legs(%{legs: legs}), do: styled_legs(legs)
  def legs(_), do: []

  def transit?(itinerary) do
    Enum.any?(itinerary.legs, &(&1[:mode] not in [nil, "WALK", "BICYCLE", "CAR"]))
  end

  def itinerary(%{itineraries: [itinerary | _]}),
    do: %{itinerary | legs: styled_legs(itinerary.legs)}

  def itinerary(_), do: nil

  @line_colors ~w(#6d28d9 #007c78 #c2410c #1d4ed8 #be185d #854d0e)

  defp styled_legs(legs) do
    {styled, _colors} = Enum.map_reduce(legs, %{}, &style_leg/2)
    styled
  end

  defp style_leg(leg, colors) do
    mode = Map.get(leg, :mode)

    if mode in [nil, "WALK", "BICYCLE", "BIKE", "CAR"] do
      color = if mode == "WALK", do: "#475569", else: "#2563eb"
      {Map.merge(leg, %{color: color, route_label: nil}), colors}
    else
      name = leg[:route_name] |> to_string() |> String.trim()
      key = {mode, leg[:agency_name], name}

      color =
        Map.get(colors, key) || Enum.at(@line_colors, rem(map_size(colors), length(@line_colors)))

      styled =
        Map.merge(leg, %{color: color, route_label: if(name == "", do: label(mode), else: name)})

      {styled, Map.put(colors, key, color)}
    end
  end

  def label("auto"), do: "Drive"
  def label("bicycle"), do: "Bike"
  def label("pedestrian"), do: "Walk"
  def label("transit"), do: "Public transport"

  def label(mode),
    do:
      mode |> to_string() |> String.replace("_", " ") |> String.downcase() |> String.capitalize()

  def timestamp(value) when is_integer(value) do
    case DateTime.from_unix(value, :millisecond) do
      {:ok, dt} -> DateTime.to_iso8601(dt)
      _ -> nil
    end
  end

  def timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> DateTime.to_iso8601(dt)
      _ -> nil
    end
  end

  def timestamp(_), do: nil

  def place_name(%{name: name}, fallback) when name in [nil, "START", "END", ""], do: fallback
  def place_name(%{name: name}, _), do: name
  def place_name(_, fallback), do: fallback

  def wait_before(legs, index) when index > 0 do
    previous = Enum.at(legs, index - 1)
    current = Enum.at(legs, index)

    with start when not is_nil(start) <- timestamp(current[:start_time]),
         finish when not is_nil(finish) <- timestamp(previous[:end_time]),
         {:ok, a, _} <- DateTime.from_iso8601(start),
         {:ok, b, _} <- DateTime.from_iso8601(finish) do
      max(0, DateTime.diff(a, b))
    else
      _ -> 0
    end
  end

  def wait_before(_, _), do: 0

  def time_status(leg) do
    case leg[:realtime] do
      true -> "Live prediction"
      false -> "Scheduled"
      _ -> "Realtime status unknown"
    end
  end

  def minutes(seconds) when is_number(seconds), do: "#{max(1, ceil(seconds / 60))} min"
  def minutes(_), do: ""

  def duration(%{itineraries: [itinerary | _]}), do: minutes(itinerary[:duration])
  def duration(%{summary: summary}), do: minutes(summary["time"])
  def duration(_), do: ""
end
