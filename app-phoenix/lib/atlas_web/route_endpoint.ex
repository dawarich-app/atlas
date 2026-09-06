defmodule AtlasWeb.RouteEndpoint do
  @moduledoc "State and validation for a directions endpoint."

  alias Atlas.Geometry.Coord
  alias Atlas.Maps.Search

  defstruct query: "", coords: nil, results: [], status: :idle, active: -1

  def new(query \\ "") do
    case coordinates(query) do
      {:ok, coords} ->
        %__MODULE__{query: query, coords: coords, status: :selected}

      :error ->
        %__MODULE__{
          query: query,
          status: if(match?({:ok, _}, Coord.parse_latlon(query)), do: :invalid, else: :idle)
        }
    end
  end

  def resolve(%{query: query, coords: coords}, query) when not is_nil(coords), do: {:ok, coords}
  def resolve(_, query), do: coordinates(query)

  def coordinates(query) do
    case Coord.parse_latlon(query) do
      {:ok, %{lat: lat, lon: lon} = coords}
      when lat >= -90 and lat <= 90 and lon >= -180 and lon <= 180 ->
        {:ok, coords}

      _ ->
        :error
    end
  end

  def search(query, viewport) do
    opts = %{query: query, limit: 6}

    opts =
      case viewport do
        [w, s, e, n] -> Map.merge(opts, %{lat: (s + n) / 2, lon: (w + e) / 2})
        _ -> opts
      end

    case Search.autocomplete(opts) do
      {:ok, result} ->
        {:ok, result.features |> Enum.filter(&valid_place?/1) |> Enum.map(&with_address/1)}

      {:error, _} ->
        {:error, :unavailable}
    end
  end

  def select(place), do: %__MODULE__{query: place.label, coords: place.coords, status: :selected}

  defp valid_place?(%{coords: %{lat: lat, lon: lon}}) do
    is_number(lat) and is_number(lon) and lat >= -90 and lat <= 90 and lon >= -180 and lon <= 180
  end

  defp valid_place?(_), do: false

  defp with_address(place) do
    address = place.address
    street = join([address[:street], address[:house_number]], " ")

    label =
      join(
        [
          place.name,
          street,
          address[:postcode],
          address[:city],
          address[:state],
          address[:country]
        ],
        ", "
      )

    %{place | label: if(label == "", do: place.label, else: label)}
  end

  defp join(parts, separator),
    do: parts |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq() |> Enum.join(separator)
end
