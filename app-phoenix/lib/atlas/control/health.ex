defmodule Atlas.Control.Health do
  @moduledoc """
  Per-capability health for the maps API. Aggregates the `services.profile`
  grouping into capability statuses (`up` | `down` | `starting`) and an
  overall (`up` | `degraded` | `down`).
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
  def summarize(statuses) when is_map(statuses) do
    caps =
      Map.new(@capabilities, fn {cap, service} ->
        {cap, normalize(Map.get(statuses, service))}
      end)

    %{status: overall(Map.values(caps)), capabilities: caps}
  end

  @spec summary() :: map()
  def summary do
    Service
    |> Repo.all()
    |> Map.new(fn s -> {s.name, s.status} end)
    |> summarize()
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
