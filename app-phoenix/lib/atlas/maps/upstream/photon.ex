defmodule Atlas.Maps.Upstream.Photon do
  alias Atlas.Maps.Upstream.Client

  def default do
    Client.build_from_env("PHOTON", "http://localhost:8001",
                          timeout: 5_000, open_timeout: 2_000)
  end

  def search(req \\ default(), opts) do
    params =
      [{"q", opts[:query]}, {"limit", opts[:limit] || 10}]
      |> maybe_add("lang", opts[:lang])
      |> maybe_add("lat", opts[:lat])
      |> maybe_add("lon", opts[:lon])
      |> maybe_add_bbox(opts[:bbox])
      |> append_osm_tags(opts[:osm_tags])

    Client.get(req, "/api", params)
  end

  def reverse(req \\ default(), opts) do
    params =
      [{"lat", opts[:lat]}, {"lon", opts[:lon]}]
      |> maybe_add("radius", opts[:radius])
      |> maybe_add("lang", opts[:lang])

    Client.get(req, "/reverse", params)
  end

  defp append_osm_tags(params, nil), do: params
  defp append_osm_tags(params, tags) when is_list(tags), do: params ++ Enum.map(tags, &{"osm_tag", &1})

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, key, val), do: params ++ [{key, val}]

  defp maybe_add_bbox(params, nil), do: params
  defp maybe_add_bbox(params, [w, s, e, n]), do: params ++ [{"bbox", "#{w},#{s},#{e},#{n}"}]
end
