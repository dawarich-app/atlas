defmodule AtlasWeb.GoldenHelper do
  @moduledoc """
  Loads captured Rails JSON fixtures from `test/fixtures/goldens/` for the
  golden-file parity harness.

  Three layers:

    * `load/1` — reads a captured Rails JSON golden by name or returns `nil`
      when none exists (harness wiring stays inert until goldens are
      captured).

    * `assert_envelope_shape/2` — structural-only check that the top-level
      envelope keys match between Phoenix output and the Rails golden. Used
      from M1 onward.

    * `assert_byte_diff/2` — full byte-diff parity check used as the M5
      cutover gate. Drops runtime-volatile `meta` fields (`timestamp`,
      `request_id`, and the `cache_hits`/`cache_misses` split — which depends
      on cache warmth and always sums to the asserted `count`) before
      comparison so the harness only fails on real structural drift, not
      clock skew or cache state.

  Until Rails goldens are captured (manual step documented in
  `scripts/M5_GOLDENS_CAPTURE.md`), `assert_byte_diff/2` is a no-op against
  `nil`, matching the existing behaviour of `assert_envelope_shape/2`.
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

  @doc """
  Byte-diff parity check used as the M5 cutover gate.

  Drops volatile fields (`meta.timestamp`, `meta.request_id`) before
  comparing. Returns `:ok` on match or when no golden is captured yet;
  raises with a formatted diff message when Phoenix output drifts from
  the captured Rails golden.
  """
  def assert_byte_diff(_actual, nil), do: :ok

  def assert_byte_diff(actual, expected) when is_map(actual) and is_map(expected) do
    actual_clean = drop_volatile(actual)
    expected_clean = drop_volatile(expected)

    if actual_clean != expected_clean do
      ExUnit.Assertions.flunk(diff_message(actual_clean, expected_clean))
    end

    :ok
  end

  def diff(actual, expected) do
    drop_volatile(actual) == drop_volatile(expected)
  end

  defp drop_volatile(%{"meta" => meta} = json) when is_map(meta) do
    cleaned_meta = Map.drop(meta, ["request_id", "timestamp", "cache_hits", "cache_misses"])
    Map.put(json, "meta", cleaned_meta)
  end

  defp drop_volatile(other), do: other

  defp diff_message(actual, expected) do
    """
    Byte-diff parity violation.

    Actual (Phoenix):
    #{Jason.encode!(actual, pretty: true)}

    Expected (Rails golden):
    #{Jason.encode!(expected, pretty: true)}

    Top-level keys:
      actual:   #{inspect(Map.keys(actual) |> Enum.sort())}
      expected: #{inspect(Map.keys(expected) |> Enum.sort())}
    """
  end
end
