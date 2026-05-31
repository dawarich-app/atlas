defmodule Atlas.Maps.Upstream.Overpass do
  alias Atlas.Maps.Upstream.Client

  def default do
    Client.build(System.get_env("OVERPASS_URL") || "http://localhost:8002",
                 timeout: env_int("OVERPASS_TIMEOUT", 25_000),
                 open_timeout: env_int("OVERPASS_OPEN_TIMEOUT", 2_000))
  end

  def around(req \\ default(), opts) do
    ql = build_query(opts)
    Client.post_raw(req, "/api/interpreter", ql)
  end

  def bbox(req \\ default(), opts) do
    ql = build_bbox_query(opts)
    Client.post_raw(req, "/api/interpreter", ql)
  end

  defp build_bbox_query(opts) do
    # Rails bbox contract: [s, w, n, e]. Overpass needs s,w,n,e clause too.
    [s, w, n, e] = opts[:bbox]
    filters = opts[:filters] || []
    limit = opts[:limit] || 300
    timeout = opts[:timeout] || 25

    bbox_clause = "#{s},#{w},#{n},#{e}"

    statements =
      case filters do
        [] ->
          ~s|node(#{bbox_clause});way(#{bbox_clause});relation(#{bbox_clause});|

        filters ->
          filters
          |> Enum.map(fn sel ->
            [k, v] = String.split(sel, "=", parts: 2)
            ~s|node["#{k}"="#{v}"](#{bbox_clause});way["#{k}"="#{v}"](#{bbox_clause});|
          end)
          |> Enum.join("")
      end

    ~s|[out:json][timeout:#{timeout}];(#{statements});out body center #{limit};|
  end

  defp build_query(opts) do
    %{lat: lat, lon: lon, radius: r} = Map.new(opts)
    tags = opts[:osm_tags] || []
    timeout = opts[:timeout] || 25

    around_clause = "around:#{r},#{lat},#{lon}"

    statements =
      case tags do
        [] ->
          ~s|node(#{around_clause});way(#{around_clause});relation(#{around_clause});|

        tags ->
          tags
          |> Enum.map(fn tag ->
            [k, v] = String.split(tag, ":", parts: 2)
            ~s|node["#{k}"="#{v}"](#{around_clause});way["#{k}"="#{v}"](#{around_clause});|
          end)
          |> Enum.join("")
      end

    ~s|[out:json][timeout:#{timeout}];(#{statements});out body center;|
  end

  defp env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      val -> String.to_integer(val)
    end
  end
end
