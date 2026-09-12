defmodule Atlas.Maps.MapMatchLimiterTest do
  use ExUnit.Case, async: true

  alias Atlas.Maps.MapMatchLimiter

  test "fails fast at capacity and admits work after checkin" do
    limiter = start_supervised!({MapMatchLimiter, name: nil, limit: 1})

    assert {:ok, token} = MapMatchLimiter.checkout(limiter)
    assert {:error, :map_match_busy, 1} = MapMatchLimiter.run(fn -> :unexpected end, limiter)

    MapMatchLimiter.checkin(token, limiter)
    assert MapMatchLimiter.run(fn -> :matched end, limiter) == :matched
  end

  test "reclaims a slot when its caller exits" do
    limiter = start_supervised!({MapMatchLimiter, name: nil, limit: 1})
    parent = self()

    holder =
      spawn(fn ->
        result = MapMatchLimiter.checkout(limiter)
        send(parent, {:slot_held, result})
        if match?({:ok, _token}, result), do: Process.sleep(:infinity)
      end)

    assert_receive {:slot_held, {:ok, _token}}
    assert {:error, :map_match_busy, 1} = MapMatchLimiter.checkout(limiter)

    Process.exit(holder, :kill)
    assert eventually_checkout(limiter)
  end

  defp eventually_checkout(limiter, attempts \\ 20)

  defp eventually_checkout(_limiter, 0), do: false

  defp eventually_checkout(limiter, attempts) do
    case MapMatchLimiter.checkout(limiter) do
      {:ok, token} ->
        MapMatchLimiter.checkin(token, limiter)
        true

      {:error, :map_match_busy, 1} ->
        Process.sleep(1)
        eventually_checkout(limiter, attempts - 1)
    end
  end
end
