defmodule AtlasWeb.GoldenHelper do
  @moduledoc """
  Loads captured Rails JSON fixtures from `test/fixtures/goldens/` for the
  golden-file parity harness.

  At M1 the harness is structural-only: when a golden is present, we assert
  the top-level envelope keys match. Byte-diff parity is M4's job and will
  layer additional comparisons on top of these helpers.

  When no golden file exists for a given name, `load/1` returns `nil` and
  the shape assertion becomes a no-op so the harness wiring is in place
  before fixtures are captured.
  """

  def load(name) do
    path = "test/fixtures/goldens/#{name}.json"

    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
    else
      nil
    end
  end

  def assert_envelope_shape(_actual, nil), do: :ok

  def assert_envelope_shape(actual, expected) when is_map(actual) and is_map(expected) do
    actual_keys = actual |> Map.keys() |> Enum.sort()
    expected_keys = expected |> Map.keys() |> Enum.sort()

    ExUnit.Assertions.assert(
      actual_keys == expected_keys,
      "envelope key mismatch: actual=#{inspect(actual_keys)} expected=#{inspect(expected_keys)}"
    )
  end

  def diff(actual, expected) do
    drop_volatile(actual) == drop_volatile(expected)
  end

  defp drop_volatile(%{"meta" => meta} = json) when is_map(meta) do
    cleaned_meta = Map.drop(meta, ["request_id", "timestamp"])
    Map.put(json, "meta", cleaned_meta)
  end

  defp drop_volatile(other), do: other
end
