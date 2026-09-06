defmodule Atlas.Control.OtpBuildConfigTest do
  use ExUnit.Case, async: true

  alias Atlas.Control.OtpBuildConfig
  alias Atlas.Control.RegionCatalog

  defp entry(country_code), do: %RegionCatalog{name: "r", country_code: country_code}

  describe "resolve/1" do
    test "resolves a single region to its country's zone" do
      assert OtpBuildConfig.resolve([entry("de")]) == {:ok, "Europe/Berlin"}
    end

    test "uppercase country codes resolve — presets are not normalised on load" do
      assert OtpBuildConfig.resolve([entry("DE")]) == {:ok, "Europe/Berlin"}
    end

    test "several regions in one country resolve to that country's zone" do
      assert OtpBuildConfig.resolve([entry("de"), entry("de")]) == {:ok, "Europe/Berlin"}
    end

    test "countries that keep the same clock all year resolve together" do
      # Berlin + Vienna is a realistic multi-select, and CET answers opening
      # hours identically for both. The chosen zone is the alphabetically first
      # of the agreeing set, so the result cannot depend on selection order.
      assert OtpBuildConfig.resolve([entry("de"), entry("at")]) == {:ok, "Europe/Berlin"}
      assert OtpBuildConfig.resolve([entry("at"), entry("de")]) == {:ok, "Europe/Berlin"}
      assert OtpBuildConfig.resolve([entry("de"), entry("nl")]) == {:ok, "Europe/Amsterdam"}
    end

    test "countries on different clocks are ambiguous" do
      # Same continent, one hour apart — the case the signature exists to catch.
      assert OtpBuildConfig.resolve([entry("de"), entry("gb")]) == :ambiguous
    end

    test "a country spanning genuinely different offsets is ambiguous" do
      for cc <- ~w(us ca au br ru mx id es pt ua cn) do
        assert OtpBuildConfig.resolve([entry(cc)]) == :ambiguous, "expected #{cc} ambiguous"
      end
    end

    test "a country whose zones differ only in pre-1970 history still resolves" do
      # Germany carries Europe/Busingen alongside Europe/Berlin, Cyprus carries
      # Asia/Famagusta alongside Asia/Nicosia. Both twins have tracked the
      # primary zone to the minute for decades, so excluding them would strand
      # the single most common region for no gain. The zone kept is the primary.
      assert OtpBuildConfig.resolve([entry("de")]) == {:ok, "Europe/Berlin"}
      assert OtpBuildConfig.resolve([entry("cy")]) == {:ok, "Asia/Nicosia"}
    end

    test "a missing country code is ambiguous" do
      assert OtpBuildConfig.resolve([entry(nil)]) == :ambiguous
      assert OtpBuildConfig.resolve([entry("")]) == :ambiguous
    end

    test "an unmapped country code is ambiguous" do
      # `europe` is what the shipped continent preset carries in COUNTRY_CODE.
      assert OtpBuildConfig.resolve([entry("europe")]) == :ambiguous
      assert OtpBuildConfig.resolve([entry("zz")]) == :ambiguous
    end

    test "one unresolvable region poisons an otherwise resolvable set" do
      # Merging Berlin with a continent extract must not claim Europe/Berlin for
      # the whole merged file.
      assert OtpBuildConfig.resolve([entry("de"), entry("europe")]) == :ambiguous
      assert OtpBuildConfig.resolve([entry("europe"), entry("de")]) == :ambiguous
    end

    test "no regions at all is ambiguous" do
      assert OtpBuildConfig.resolve([]) == :ambiguous
    end
  end

  describe "render/1" do
    test "renders osmDefaults.timeZone as OTP's schema expects" do
      assert %{"osmDefaults" => %{"timeZone" => "Europe/Berlin"}} =
               "Europe/Berlin" |> OtpBuildConfig.render() |> Jason.decode!()
    end

    test "renders nothing else — every extra key is a build parameter we did not choose" do
      decoded = "Europe/Berlin" |> OtpBuildConfig.render() |> Jason.decode!()
      assert Map.keys(decoded) == ["osmDefaults"]
      assert decoded |> Map.fetch!("osmDefaults") |> Map.keys() == ["timeZone"]
    end
  end

  describe "the generated table" do
    test "maps every country to a plausible IANA zone and a parseable signature" do
      for {cc, {zone, signature}} <- OtpBuildConfig.country_zones() do
        assert zone =~ ~r{^[A-Za-z_]+/[A-Za-z0-9_+/-]+$}, "#{cc}: implausible zone #{zone}"

        assert signature =~ ~r/^[+-]\d{2}:\d{2}@\d+(,[+-]\d{2}:\d{2}@\d+)*$/,
               "#{cc}: unparseable signature #{signature}"
      end
    end

    test "every signature starts at sample 0, so timelines are comparable" do
      for {cc, {_zone, signature}} <- OtpBuildConfig.country_zones() do
        assert String.ends_with?(hd(String.split(signature, ",")), "@0"),
               "#{cc}: signature does not start at sample 0"
      end
    end

    test "still covers the country codes the shipped catalog leans on" do
      # A regression guard on regeneration: if the table were rebuilt from a
      # trimmed tz database, the flagship regions must not silently stop
      # resolving and drop OTP back to its warning.
      for cc <- ~w(de nl fr pl ch at be cz dk se no it) do
        assert {:ok, _} = OtpBuildConfig.resolve([entry(cc)])
      end
    end
  end
end
