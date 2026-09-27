defmodule Atlas.Control.Health do
  @moduledoc """
  Per-capability health for the maps API. Container state supplies the default
  statuses; a configured Photon upstream is probed directly so externally
  managed Photon does not appear down when its Atlas control record is stale.
  """
  alias Atlas.Control.Service
  alias Atlas.Repo

  @capabilities %{
    "geocoding" => "photon",
    "routing" => "valhalla",
    "pois" => "overpass",
    "transit" => "otp"
  }

  @spec capabilities() :: %{String.t() => String.t()}
  def capabilities, do: @capabilities

  @spec summarize(%{optional(String.t()) => term()}) :: map()
  def summarize(statuses, backend \\ "otp") when is_map(statuses) do
    caps =
      Map.new(Map.put(@capabilities, "transit", backend), fn {cap, service} ->
        {cap, normalize(Map.get(statuses, service))}
      end)

    %{status: overall(Map.values(caps)), capabilities: caps}
  end

  @spec summary(keyword()) :: map()
  def summary(opts \\ []) do
    statuses =
      Service
      |> Repo.all()
      |> Map.new(fn s -> {s.name, s.status} end)
      |> with_live_photon_status(opts)

    summarize(
      statuses,
      Keyword.get_lazy(opts, :transit_backend, &Atlas.Settings.transit_backend/0)
    )
  end

  # Container state is not authoritative when Photon is supplied through
  # PHOTON_URL (including a separate Compose deployment). Probe the same
  # upstream used by the public geocoding API instead.
  defp with_live_photon_status(statuses, opts) do
    case Keyword.get_lazy(opts, :photon_url, fn -> System.get_env("PHOTON_URL") end) do
      url when is_binary(url) and url != "" ->
        probe = Keyword.get(opts, :photon_probe, &photon_available?/1)
        Map.put(statuses, "photon", if(probe.(url), do: :ready, else: :stopped))

      _ ->
        statuses
    end
  end

  defp photon_available?(url) do
    req =
      Req.new(
        base_url: url,
        connect_options: [timeout: 1_000, protocols: [:http1]],
        receive_timeout: 2_000,
        retry: false
      )

    case Req.get(req, url: "/status") do
      {:ok, %Req.Response{status: 200, body: %{"status" => "Ok"}}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp normalize(s) when s in ["ready", :ready], do: "up"
  defp normalize(s) when s in ["stopped", "error", :stopped, :error, nil], do: "down"
  defp normalize(s) when s in [:unknown, "unknown"], do: "down"
  defp normalize(_), do: "starting"

  defp overall(values) do
    cond do
      Enum.all?(values, &(&1 == "up")) -> "up"
      Enum.all?(values, &(&1 == "down")) -> "down"
      true -> "degraded"
    end
  end
end
