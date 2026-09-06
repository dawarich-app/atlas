defmodule AtlasWeb.SearchMarkers do
  @moduledoc """
  Turns `Atlas.Maps.Place` results into the payload the map hook draws.

  A marker is only as useful as what it says when clicked, so a point carries
  the category and a one-line address alongside the coordinates — everything
  the popup renders. Photon gives us no OSM tag block, so there are no opening
  hours, phone or website rows here: the popup shows what we actually have
  rather than a scaffold of empty fields.
  """

  alias AtlasWeb.PlaceIcons

  @doc "Marker points for `places`, dropping any that cannot be placed on a map."
  @spec points([map()]) :: [map()]
  def points(places) do
    places
    |> Enum.filter(&placeable?/1)
    |> Enum.map(fn place ->
      %{
        id: place.id,
        lat: place.coords.lat,
        lon: place.coords.lon,
        label: place.label,
        category: place |> Map.get(:type) |> PlaceIcons.for() |> elem(1),
        address: address_line(Map.get(place, :address)),
        region: region_line(Map.get(place, :admin)),
        osm_url: osm_url(Map.get(place, :id))
      }
    end)
  end

  @osm_kinds %{"N" => "node", "W" => "way", "R" => "relation"}

  # `Place.id` is Photon's `osm_type:osm_id` — "N:240109189". openstreetmap.org
  # wants /node/240109189, so the letter has to be expanded. The Rails popup
  # linked the raw id straight through, which 404s. Anything we cannot parse
  # gets no link at all: a dead link is worse than none.
  defp osm_url(id) when is_binary(id) do
    with [kind, ref] <- String.split(id, ":", parts: 2),
         {:ok, path} <- Map.fetch(@osm_kinds, kind),
         true <- ref =~ ~r/^\d+$/ do
      "https://www.openstreetmap.org/#{path}/#{ref}"
    else
      _ -> nil
    end
  end

  defp osm_url(_), do: nil

  # Photon occasionally returns a feature with an empty geometry. A marker at
  # [nil, nil] throws inside MapLibre and takes the rest of the list with it.
  defp placeable?(%{coords: %{lat: lat, lon: lon}}) when is_number(lat) and is_number(lon),
    do: true

  defp placeable?(_), do: false

  defp address_line(address) when is_map(address) do
    street = join_present([address[:street], address[:house_number]], " ")
    town = join_present([address[:postcode], address[:city]], " ")

    case join_present([street, town], ", ") do
      "" -> nil
      line -> line
    end
  end

  defp address_line(_), do: nil

  # State and country only. City and postcode already appear in the address
  # line, and a popup that says "Berlin" twice reads like a rendering bug.
  defp region_line(admin) when is_map(admin) do
    case join_present([admin[:state], admin[:country]], ", ") do
      "" -> nil
      line -> line
    end
  end

  defp region_line(_), do: nil

  defp join_present(parts, separator) do
    parts
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(separator)
  end
end
