defmodule Atlas.Maps.ReverseBatchTest do
  use ExUnit.Case, async: false
  alias Atlas.Maps.Reverse

  setup do
    Cachex.clear(:reverse_cache)
    bypass = Bypass.open()
    System.put_env("PHOTON_URL", "http://localhost:#{bypass.port}")
    System.put_env("PLACEHOLDER_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("PHOTON_URL"); System.delete_env("PLACEHOLDER_URL") end)
    {:ok, bypass: bypass}
  end

  defp expect_reverse_ok(bypass) do
    Bypass.expect(bypass, fn conn ->
      case conn.request_path do
        "/reverse" -> Plug.Conn.resp(conn, 200, ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"X","city":"Y","country":"Z"}}]}))
        "/parser/search" -> Plug.Conn.resp(conn, 200, "[]")
      end
    end)
  end

  test "batch returns {:ok, summary} with one result per input coord and cache misses on first run", %{bypass: bypass} do
    expect_reverse_ok(bypass)

    coords = [%{lat: 52.5, lon: 13.4}, %{lat: 48.1, lon: 11.5}]
    assert {:ok, summary} = Reverse.batch(%{coords: coords})

    assert length(summary.results) == 2
    assert summary.cache_hits == 0
    assert summary.cache_misses == 2
    assert summary.upstream_errors == 0
  end

  test "batch dedupes coords within grid precision (4 decimals) on cache key", %{bypass: bypass} do
    expect_reverse_ok(bypass)

    # Same to 4 decimals; second call should hit cache
    coord_a = %{lat: 52.500011, lon: 13.400011}
    coord_b = %{lat: 52.500012, lon: 13.400012}

    assert {:ok, _} = Reverse.batch(%{coords: [coord_a]})
    assert {:ok, summary} = Reverse.batch(%{coords: [coord_b]})
    assert summary.cache_hits == 1
    assert summary.cache_misses == 0
  end

  test "batch returns {:error, :too_many, 500} when over MAX_COORDS=500" do
    coords = for n <- 1..501, do: %{lat: 52.0 + n / 10000, lon: 13.0 + n / 10000}
    assert {:error, :too_many, 500} = Reverse.batch(%{coords: coords})
  end

  test "batch accepts exactly MAX_COORDS=500 items", %{bypass: bypass} do
    Bypass.stub(bypass, "GET", "/reverse", fn conn -> Plug.Conn.resp(conn, 200, ~s({"features":[]})) end)
    Bypass.stub(bypass, "GET", "/parser/search", fn conn -> Plug.Conn.resp(conn, 200, "[]") end)

    coords = for n <- 1..500, do: %{lat: 52.0 + n / 100_000, lon: 13.0 + n / 100_000}
    assert {:ok, summary} = Reverse.batch(%{coords: coords})
    assert length(summary.results) == 500
  end

  test "batch separates cache by lang", %{bypass: bypass} do
    expect_reverse_ok(bypass)

    coord = [%{lat: 52.5, lon: 13.4}]

    {:ok, result_en} = Reverse.batch(%{coords: coord})
    assert result_en.cache_misses == 1

    {:ok, result_de} = Reverse.batch(%{coords: coord, lang: "de"})
    assert result_de.cache_misses == 1
  end

  test "batch echoes per-coord id in result", %{bypass: bypass} do
    expect_reverse_ok(bypass)

    coords = [
      %{lat: 52.5, lon: 13.4, id: "point-1"},
      %{lat: 48.1, lon: 11.5, id: "point-2"}
    ]

    {:ok, summary} = Reverse.batch(%{coords: coords})
    ids = Enum.map(summary.results, & &1.id)
    assert ids == ["point-1", "point-2"]
  end

  test "batch per-item bad-input does not halt rest of batch", %{bypass: bypass} do
    expect_reverse_ok(bypass)

    coords = [
      %{lat: 52.5, lon: 13.4, id: "good"},
      %{lat: "not-a-number", lon: 13.4, id: "bad"},
      %{lat: 48.1, lon: 11.5, id: "good2"}
    ]

    {:ok, summary} = Reverse.batch(%{coords: coords})
    assert length(summary.results) == 3

    [r1, r2, r3] = summary.results
    assert r1.id == "good"
    assert is_map(r1.here)

    assert r2.id == "bad"
    assert r2.error =~ "numeric"
    # Echo raw input
    assert r2.coord == %{raw_lat: "not-a-number", raw_lon: 13.4}

    assert r3.id == "good2"
  end

  test "batch accepts string lat/lon via Float.parse", %{bypass: bypass} do
    expect_reverse_ok(bypass)

    coords = [%{lat: "52.5", lon: "13.4", id: "str"}]
    {:ok, summary} = Reverse.batch(%{coords: coords})

    [r] = summary.results
    assert r.id == "str"
    assert r.coord == %{lat: 52.5, lon: 13.4}
    refute Map.has_key?(r, :error)
  end

  test "batch uses 30-day TTL on cache entries", %{bypass: bypass} do
    expect_reverse_ok(bypass)

    coord = [%{lat: 52.5, lon: 13.4}]
    assert {:ok, _} = Reverse.batch(%{coords: coord})

    # Cache key must be string-namespaced "rg:v1:<lat>:<lon>:<lang>"
    key = "rg:v1:52.5:13.4:default"

    {:ok, ttl} = Cachex.ttl(:reverse_cache, key)
    # ~30 days in ms; allow a window for test execution time
    assert ttl > :timer.hours(720) - :timer.minutes(5)
    assert ttl <= :timer.hours(720)
  end

  test "batch cache key includes lang component", %{bypass: bypass} do
    expect_reverse_ok(bypass)

    {:ok, _} = Reverse.batch(%{coords: [%{lat: 52.5, lon: 13.4}], lang: "de"})

    de_key = "rg:v1:52.5:13.4:de"
    default_key = "rg:v1:52.5:13.4:default"

    {:ok, de_val} = Cachex.get(:reverse_cache, de_key)
    {:ok, default_val} = Cachex.get(:reverse_cache, default_key)

    assert is_map(de_val)
    refute default_val
  end
end
