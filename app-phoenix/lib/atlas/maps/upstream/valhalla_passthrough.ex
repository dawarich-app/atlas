defmodule Atlas.Maps.Upstream.ValhallaPassthrough do
  @moduledoc """
  Raw passthrough to the internal Valhalla service, the counterpart of
  `Atlas.Maps.Upstream.PhotonPassthrough`.

  Forwards the request's query string verbatim and returns Valhalla's status
  and body untouched: no normalization, no envelope, Valhalla's own errors.
  Consumed by `AtlasWeb.Api.V1.ValhallaController` so external proxies
  (chibigeo) can offer a byte-faithful Valhalla API next to Atlas's own
  `/api/v1/route`.

  Only `/route` is mirrored. Matrix, isochrone and trace requests cost far more
  than a route and need their own limits before they are opened.
  """
  alias Atlas.Maps.Upstream.Client

  @paths %{route: "/route"}

  def forward(action, query_string) when is_map_key(@paths, action) do
    base_url = System.get_env("VALHALLA_URL") || "http://localhost:8004"

    req =
      Req.new(
        base_url: base_url,
        connect_options: [
          timeout: Client.env_int("VALHALLA_OPEN_TIMEOUT", 2_000),
          protocols: [:http1]
        ],
        receive_timeout: Client.env_int("VALHALLA_TIMEOUT", 15_000),
        retry: false,
        decode_body: false
      )

    case Req.get(req, url: Map.fetch!(@paths, action) <> qs(query_string)) do
      {:ok, %Req.Response{status: status, body: body}} -> {:ok, %{status: status, body: body}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp qs(""), do: ""
  defp qs(query_string), do: "?" <> query_string
end
