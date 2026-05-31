defmodule Atlas.Maps.Upstream.Valhalla do
  alias Atlas.Maps.Upstream.Client

  @modes ~w[auto bicycle pedestrian]

  def default do
    Client.build_from_env("VALHALLA", "http://localhost:8004",
                          timeout: 15_000, open_timeout: 2_000)
  end

  def route(req \\ default(), opts) do
    mode = opts[:mode] || "auto"
    unless mode in @modes, do: raise(ArgumentError, "invalid mode #{mode}")

    body = %{
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

  defp maybe_add_costing_options(body, "auto", %{} = options) when map_size(options) > 0 do
    auto_opts =
      %{}
      |> maybe_put(:use_tolls, 0.0, options[:avoid_tolls])
      |> maybe_put(:use_highways, 0.0, options[:avoid_highways])
      |> maybe_put(:use_ferry, 0.0, options[:avoid_ferries])

    if map_size(auto_opts) > 0, do: Map.put(body, :costing_options, %{auto: auto_opts}), else: body
  end

  defp maybe_add_costing_options(body, _mode, _options), do: body

  defp maybe_put(map, _key, _value, falsy) when falsy in [nil, false], do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)
end
