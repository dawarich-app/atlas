defmodule Atlas.Maps.SearchMatchTest do
  use ExUnit.Case, async: true
  alias Atlas.Maps.SearchMatch

  defp matches?(query, properties),
    do: SearchMatch.matches?(SearchMatch.compile(query), %{"properties" => properties})

  test "qualified place query must match the name or address, not just its district or country" do
    q = "Adlershof, Berlin, Deutschland"
    assert matches?(q, %{"name" => "Adlershof", "city" => "Berlin", "country" => "Deutschland"})

    assert matches?(q, %{
             "name" => "Heizkraftwerk Berlin-Adlershof",
             "city" => "Berlin",
             "country" => "Deutschland"
           })

    refute matches?(q, %{
             "name" => "REWE",
             "district" => "Adlershof",
             "city" => "Berlin",
             "country" => "Deutschland"
           })

    refute matches?(q, %{
             "name" => "Berliner Promenade",
             "city" => "Saarbrücken",
             "country" => "Deutschland"
           })

    refute matches?(q, %{"name" => "Adlershof", "city" => "Wittmund", "country" => "Deutschland"})
  end

  test "address searches can match street and house number even when a business has another name" do
    assert matches?("Rudower Chaussee 25, Berlin", %{
             "name" => "Hotel",
             "street" => "Rudower Chaussee",
             "housenumber" => "25",
             "city" => "Berlin"
           })

    refute matches?("Rudower Chaussee 25, Berlin", %{
             "name" => "Hotel",
             "street" => "Rudower Chaussee",
             "housenumber" => "12",
             "city" => "Berlin"
           })
  end

  test "brands, accents, prefixes and unpunctuated location context remain searchable" do
    assert matches?("McDonald's Berlin", %{"name" => "McDonald’s", "city" => "Berlin"})
    assert matches?("McDonald's", %{"name" => "McDonald´s Dillingen/Saar"})
    assert matches?("Cafe", %{"name" => "Café Central"})
    assert matches?("Adlershof", %{"name" => "Adlershofer Brücke"})
    refute matches?("Adlershof", %{"name" => "Adlerhof"})
    refute matches?("Berlin", %{"name" => "REWE", "city" => "Berlin"})
    assert matches?("", %{"name" => "REWE", "city" => "Berlin"})
  end
end
