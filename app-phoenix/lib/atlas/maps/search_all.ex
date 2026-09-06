defmodule Atlas.Maps.SearchAll do
  @moduledoc """
  Collects map search matches from Photon's installed dataset, independently of
  the viewport. A full page is subdivided spatially until every child returns
  fewer than the upstream page limit. Boundaries overlap, so OSM IDs are deduped.

  Safety limits and failed cells produce an explicitly incomplete result. They
  never turn the currently collected points into a claimed exhaustive count.
  """

  alias Atlas.Maps.{Place, SearchMatch, Upstream.Photon}

  @page_size 50
  @world [-180.0, -90.0, 180.0, 90.0]

  def run(query, opts \\ []) do
    state = %{
      queue: [{Keyword.get(opts, :bbox, @world), 0}],
      places: %{},
      suggestions: [],
      complete: true,
      requests: 0,
      deadline: System.monotonic_time(:millisecond) + Keyword.get(opts, :timeout, 60_000),
      max_requests: Keyword.get(opts, :max_requests, 4096),
      max_depth: Keyword.get(opts, :max_depth, 32),
      page_size: Keyword.get(opts, :page_size, @page_size),
      fetch: Keyword.get(opts, :fetch, &Photon.search/1),
      progress: Keyword.get(opts, :on_progress, fn _ -> :ok end),
      query: String.trim(query),
      match: SearchMatch.compile(query),
      osm_tags: Keyword.get(opts, :osm_tags),
      concurrency: Keyword.get(opts, :concurrency, 4),
      request_timeout: Keyword.get(opts, :request_timeout, 10_000)
    }

    collect(state)
  end

  defp collect(%{queue: []} = state), do: result(state)

  defp collect(state) do
    if state.requests >= state.max_requests or
         System.monotonic_time(:millisecond) >= state.deadline do
      result(%{state | complete: false})
    else
      {batch, pending} =
        Enum.split(state.queue, min(state.concurrency, state.max_requests - state.requests))

      fetch = state.fetch
      query = state.query
      page_size = state.page_size
      osm_tags = state.osm_tags

      responses =
        Task.async_stream(
          batch,
          fn {bbox, _depth} ->
            fetch.(
              query: query,
              limit: page_size,
              bbox: bbox,
              dedupe: false,
              osm_tags: osm_tags
            )
          end,
          max_concurrency: state.concurrency,
          timeout: state.request_timeout,
          on_timeout: :kill_task
        )

      state = %{state | queue: pending, requests: state.requests + length(batch)}
      state = Enum.zip(batch, responses) |> Enum.reduce(state, &consume/2)
      if state.queue != [], do: state.progress.(result(%{state | complete: false}))
      collect(state)
    end
  end

  defp consume({{bbox, depth}, {:ok, {:ok, %{"features" => features}}}}, state)
       when is_list(features) do
    matches = Enum.filter(features, &SearchMatch.matches?(state.match, &1))
    places = Enum.reduce(matches, state.places, &add_feature/2)

    suggestions =
      if state.suggestions == [] do
        matches |> Enum.map(&Place.from_photon_feature/1) |> Enum.reject(&is_nil/1)
      else
        state.suggestions
      end

    state = %{state | places: places, suggestions: suggestions}

    cond do
      length(features) < state.page_size -> state
      # A full page of unrelated fallback suggestions must not trigger a scan
      # of every address in the dataset. Photon ranks results rather than
      # exposing an exact match count: retain an honest incomplete flag.
      matches == [] -> %{state | complete: false}
      depth >= state.max_depth -> %{state | complete: false}
      true -> %{state | queue: state.queue ++ Enum.map(split(bbox), &{&1, depth + 1})}
    end
  end

  defp consume(_failure, state), do: %{state | complete: false}

  defp add_feature(feature, places) do
    case Place.from_photon_feature(feature) do
      %{coords: %{lat: lat, lon: lon}} = place when is_number(lat) and is_number(lon) ->
        key = if place.id == "", do: {lon, lat, place.label}, else: place.id
        Map.put_new(places, key, place)

      _ ->
        places
    end
  end

  defp split([w, s, e, n]) when e - w >= n - s do
    mid = (w + e) / 2
    [[w, s, mid, n], [mid, s, e, n]]
  end

  defp split([w, s, e, n]) do
    mid = (s + n) / 2
    [[w, s, e, mid], [w, mid, e, n]]
  end

  defp result(state) do
    %{
      features: state.places |> Map.values() |> Enum.sort_by(&{&1.label, &1.id}),
      complete: state.complete,
      suggestions: state.suggestions,
      requests: state.requests
    }
  end
end
