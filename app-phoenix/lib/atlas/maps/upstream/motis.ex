defmodule Atlas.Maps.Upstream.Motis do
  @moduledoc "MOTIS v6 transit adapter. Direct walking results are deliberately excluded."
  alias Atlas.Maps.Upstream.Client

  def default, do: Client.build_from_env("MOTIS", "http://localhost:8081", timeout: 15_000)

  def plan(req \\ default(), opts) do
    opts = Map.new(opts)

    params = [
      fromPlace: coordinate(opts.from),
      toPlace: coordinate(opts.to),
      time: seconds_precision(datetime(opts)),
      arriveBy: opts[:arrive_by] in [true, "true", "1", 1, "yes"],
      transitModes: transit_modes(opts[:modes]),
      preTransitModes: "WALK",
      postTransitModes: "WALK",
      useRoutedTransfers: true,
      pedestrianSpeed: 1.33,
      numItineraries: opts[:num] || 3
    ]

    with {:ok, body} <- Client.get(req, "/api/v6/plan", params) do
      {:ok,
       %{
         "plan" => %{
           "from" => body["from"],
           "to" => body["to"],
           "itineraries" => Enum.map(body["itineraries"] || [], &itinerary/1)
         }
       }}
    end
  end

  # MOTIS 2.11.2 misreads fractional ISO timestamps as a different date.
  # Normalize offsets and drop sub-second precision for every input path.
  defp seconds_precision(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      _ -> value
    end
  end

  defp coordinate(point), do: "#{point.lat},#{point.lon}"
  defp datetime(%{datetime: value}), do: value
  defp datetime(%{date_time: value}), do: value

  defp datetime(%{date: date, time: time}) do
    value = "#{date}T#{time}"
    if String.match?(value, ~r/(Z|[+-]\d{2}:?\d{2})$/), do: value, else: value <> "Z"
  end

  defp datetime(_), do: DateTime.to_iso8601(DateTime.utc_now())

  defp transit_modes(nil), do: "TRANSIT"

  defp transit_modes(modes) do
    modes
    |> String.upcase()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "WALK"))
    |> Enum.join(",")
  end

  defp itinerary(it) do
    legs = it["legs"] || []

    it
    |> Map.put("legs", Enum.map(legs, &leg/1))
    |> Map.put(
      "walkDistance",
      legs
      |> Enum.filter(&(&1["mode"] == "WALK"))
      |> Enum.reduce(0, &((&1["distance"] || 0) + &2))
    )
  end

  defp nonempty(""), do: nil
  defp nonempty(value), do: value

  defp leg(leg) do
    # MOTIS uses finer rail classes than Atlas's existing transit renderer.
    mode =
      case leg["mode"] do
        value
        when value in ~w(SUBURBAN HIGHSPEED LONG_DISTANCE LONG_DISTANCE_FAST REGIONAL REGIONAL_FAST NIGHT) ->
          "RAIL"

        "METRO" ->
          "SUBWAY"

        value ->
          value
      end

    leg
    |> Map.put("mode", mode)
    |> Map.put(
      "routeShortName",
      nonempty(leg["routeShortName"]) || leg["displayName"] || leg["routeLongName"]
    )
  end
end
