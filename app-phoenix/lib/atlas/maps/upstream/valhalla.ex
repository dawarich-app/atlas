defmodule Atlas.Maps.Upstream.Valhalla do
  @moduledoc """
  Valhalla client for point-to-point routing (`/route`) and map matching
  (`/trace_route`), over the `auto`, `bicycle` and `pedestrian` costings.
  """

  alias Atlas.Maps.Upstream.Client

  @modes ~w[auto bicycle pedestrian]
  @shape_matches ~w[map_snap edge_walk walk_or_snap]
  @trace_option_keys ~w[search_radius gps_accuracy breakage_distance]a

  @default_url "http://localhost:8004"
  @match_timeout 60_000

  def default do
    Client.build_from_env("VALHALLA", @default_url, timeout: 15_000, open_timeout: 2_000)
  end

  @doc """
  Client for `/trace_route`, which needs a far longer receive timeout than
  `default/0`: matching a multi-thousand-point trace is minutes of work where
  an A-to-B route is milliseconds. Override with `VALHALLA_MATCH_TIMEOUT`.
  """
  def match_default do
    Client.build(System.get_env("VALHALLA_URL") || @default_url,
      timeout: Client.env_int("VALHALLA_MATCH_TIMEOUT", @match_timeout),
      open_timeout: Client.env_int("VALHALLA_OPEN_TIMEOUT", 2_000)
    )
  end

  @doc "Costings this client accepts. Valhalla has no rail or ferry costing."
  def modes, do: @modes

  @doc "Accepted `shape_match` strategies."
  def shape_matches, do: @shape_matches

  def route(req \\ default(), opts) do
    mode = opts[:mode] || "auto"
    unless mode in @modes, do: raise(ArgumentError, "invalid mode #{mode}")

    body =
      %{
        locations: [
          %{lat: opts[:from][:lat], lon: opts[:from][:lon]},
          %{lat: opts[:to][:lat], lon: opts[:to][:lon]}
        ],
        costing: mode,
        directions_options: %{units: "kilometers"}
      }
      |> maybe_add_costing_options(mode, opts[:options])

    Client.post(req, "/route", body)
  end

  @doc """
  Map-match a recorded trace onto the road network.

  `:shape` is a list of `%{lat:, lon:}` maps, optionally carrying `:time`
  (epoch seconds) and `:accuracy` (metres) — both materially improve the
  match, since Meili weights candidate edges by GPS noise and elapsed time.

  Returns the same `{"trip" => ...}` envelope as `route/2`.
  """
  def trace_route(req \\ nil, opts) do
    req = req || match_default()
    mode = opts[:mode] || "auto"
    shape_match = opts[:shape_match] || "map_snap"

    unless mode in @modes, do: raise(ArgumentError, "invalid mode #{mode}")

    unless shape_match in @shape_matches do
      raise(ArgumentError, "invalid shape_match #{shape_match}")
    end

    body =
      %{
        shape: Enum.map(opts[:shape] || [], &shape_point/1),
        costing: mode,
        shape_match: shape_match,
        directions_options: %{units: "kilometers"}
      }
      |> maybe_add_trace_options(opts[:trace_options])

    Client.post(req, "/trace_route", body)
  end

  # Only the keys actually present are emitted: Valhalla rejects a null `time`
  # on a shape point, so a nil-filled map is worse than an absent key.
  defp shape_point(point) do
    point
    |> Map.take([:lat, :lon, :time, :accuracy])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp maybe_add_trace_options(body, %{} = options) when map_size(options) > 0 do
    trace_options =
      options
      |> Map.take(@trace_option_keys)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    if map_size(trace_options) > 0,
      do: Map.put(body, :trace_options, trace_options),
      else: body
  end

  defp maybe_add_trace_options(body, _options), do: body

  defp maybe_add_costing_options(body, "auto", %{} = options) when map_size(options) > 0 do
    auto_opts =
      %{}
      |> maybe_put(:use_tolls, 0.0, options[:avoid_tolls])
      |> maybe_put(:use_highways, 0.0, options[:avoid_highways])
      |> maybe_put(:use_ferry, 0.0, options[:avoid_ferries])

    if map_size(auto_opts) > 0,
      do: Map.put(body, :costing_options, %{auto: auto_opts}),
      else: body
  end

  defp maybe_add_costing_options(body, _mode, _options), do: body

  defp maybe_put(map, _key, _value, falsy) when falsy in [nil, false], do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)
end
