defmodule Atlas.Maps.Upstream.Libpostal do
  @moduledoc """
  libpostal client — parses a free-text address into labelled components.

  Used to canonicalise a query before it reaches the geocoder; falls back to the
  raw input when parsing yields nothing.
  """

  alias Atlas.Maps.Upstream.Client

  def default do
    Client.build_from_env("LIBPOSTAL", "http://localhost:8080",
      timeout: 5_000,
      open_timeout: 2_000
    )
  end

  def normalize(req \\ default(), address) when is_binary(address) do
    case Client.get(req, "/parser", [{"address", address}]) do
      {:ok, components} when is_list(components) ->
        canonical = Enum.map_join(components, " ", & &1["value"])
        %{query: if(canonical == "", do: address, else: canonical), components: components}

      _ ->
        %{query: address, components: []}
    end
  end
end
