defmodule Atlas.Maps.Upstream.PhotonPassthrough do
  @moduledoc """
  Raw passthrough to the internal Photon service.

  Forwards the request's query string verbatim (preserving repeated keys like
  `osm_tag`) and returns Photon's status and body untouched — no
  normalization, no envelope. Consumed by `AtlasWeb.Api.V1.PhotonController`
  so external proxies (chibigeo) can offer a byte-faithful Photon API.
  """
  alias Atlas.Maps.Upstream.Client

  @paths %{search: "/api", reverse: "/reverse", lookup: "/lookup", status: "/status"}

  def forward(action, query_string) when is_map_key(@paths, action) do
    base_url = System.get_env("PHOTON_URL") || "http://localhost:8001"
    timeout = Client.env_int("PHOTON_TIMEOUT", 10_000)
    open_timeout = Client.env_int("PHOTON_OPEN_TIMEOUT", 2_000)

    req =
      Req.new(
        base_url: base_url,
        connect_options: [timeout: open_timeout, protocols: [:http1]],
        receive_timeout: timeout,
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
