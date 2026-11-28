defmodule Atlas.Maps.Transport do
  @moduledoc "MOTIS-backed map stops, service shapes, and departure boards."
  alias Atlas.Maps.Upstream.{Client, Motis}

  @stop_limit 1000
  @line_limit 600

  def stops([west, south, east, north]) do
    # grouped=true needs MOTIS's optional adr_extend index. Platform-level stops
    # work with every timetable import and retain exact departure-board IDs.
    case Client.get(Motis.default(), "/api/v6/map/stops",
           min: "#{south},#{west}",
           max: "#{north},#{east}"
         ) do
      {:ok, stops} when is_list(stops) ->
        {:ok, Enum.take(stops, @stop_limit), %{truncated: length(stops) > @stop_limit}}

      {:ok, _} ->
        malformed()

      error ->
        error
    end
  end

  def lines([west, south, east, north], zoom) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    params = [
      min: "#{south},#{west}",
      max: "#{north},#{east}",
      zoom: zoom,
      precision: 5,
      startTime: DateTime.to_iso8601(now),
      endTime: now |> DateTime.add(3600) |> DateTime.to_iso8601()
    ]

    case Client.get(Motis.default(), "/api/v6/map/trips", params) do
      {:ok, lines} when is_list(lines) ->
        unique =
          Enum.filter(lines, &is_map/1)
          |> Enum.uniq_by(fn line ->
            trip = List.first(line["trips"] || []) || %{}
            {line["polyline"], line["mode"], trip["displayName"] || trip["routeShortName"]}
          end)

        {:ok, Enum.take(unique, @line_limit), %{truncated: length(unique) > @line_limit}}

      # MOTIS limits trip density before returning shapes. Keep stops usable at
      # city scale and signal that the user needs a smaller area for lines.
      {:error, %Client.BadResponse{status: 422, body: %{"error" => "too many trips"}}} ->
        {:ok, [], %{truncated: true, zoom_in: true}}

      {:ok, _} ->
        malformed()

      error ->
        error
    end
  end

  def departures(id) do
    # MOTIS 2.11.2 can omit the queried rail platform from a zero-radius search.
    # Use one meter and filter by ID to exclude co-located platforms.
    params = [
      stopId: id,
      n: 20,
      arriveBy: false,
      radius: 1,
      exactRadius: true,
      time: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    ]

    case Client.get(Motis.default(), "/api/v6/stoptimes", params) do
      {:ok, %{"stopTimes" => times, "place" => place} = body}
      when is_list(times) and is_map(place) ->
        departures =
          Enum.filter(times, fn
            %{"place" => %{"stopId" => ^id}} -> true
            _ -> false
          end)

        {:ok, Map.put(body, "stopTimes", Enum.take(departures, 40)),
         %{truncated: length(departures) > 40}}

      {:ok, _} ->
        malformed()

      error ->
        error
    end
  end

  def trip(id) do
    case Client.get(Motis.default(), "/api/v6/trip", tripId: id, detailedLegs: true) do
      {:ok, %{"legs" => legs} = body} when is_list(legs) ->
        {:ok, body, %{}}

      {:ok, _} ->
        malformed()

      error ->
        error
    end
  end

  defp malformed,
    do: {:error, %Client.BadResponse{message: "unexpected MOTIS transport response", status: 200}}
end
