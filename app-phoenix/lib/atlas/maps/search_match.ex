defmodule Atlas.Maps.SearchMatch do
  @moduledoc "Keeps geocoder fallback suggestions out of map search matches."

  @identity ~w(name street housenumber postcode)
  @context ~w(city district locality county state country countrycode)

  def compile(query) do
    [subject | context] = String.split(query, ",", trim: false)

    %{
      subject: tokens(subject),
      context: tokens(Enum.join(context, " ")),
      qualified?: context != []
    }
  end

  def matches?(%{subject: [], context: []}, _feature), do: true

  def matches?(query, %{"properties" => props}) do
    identity = field_tokens(props, @identity)
    context = field_tokens(props, @context)
    all = identity ++ context

    if query.qualified? do
      contains_all?(identity, query.subject) and contains_all?(all, query.context)
    else
      contains_all?(all, query.subject) and
        Enum.any?(query.subject, &contains_all?(identity, [&1]))
    end
  end

  def matches?(_query, _feature), do: false

  def in_city?(_feature, city) when city in [nil, ""], do: true

  def in_city?(%{"properties" => props}, city) when is_binary(city) do
    wanted = tokens(city)
    Enum.any?(~w(city district locality), fn key -> tokens(props[key] || "") == wanted end)
  end

  def in_city?(_, _), do: false

  defp field_tokens(props, keys) do
    keys
    |> Enum.map(&Map.get(props, &1, ""))
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
    |> tokens()
  end

  defp contains_all?(fields, words) do
    Enum.all?(words, fn word ->
      if String.match?(word, ~r/^\d+$/),
        do: word in fields,
        else: Enum.any?(fields, &String.starts_with?(&1, word))
    end)
  end

  defp tokens(text) do
    text
    |> String.downcase()
    |> String.replace(~r/['’‘`´ʼ＇]/u, "")
    |> :unicode.characters_to_nfkd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
  end
end
