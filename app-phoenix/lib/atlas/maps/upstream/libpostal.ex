defmodule Atlas.Maps.Upstream.Libpostal do
  alias Atlas.Maps.Upstream.Client

  def default do
    Client.build_from_env("LIBPOSTAL", "http://localhost:8080",
                          timeout: 5_000, open_timeout: 2_000)
  end

  def normalize(req \\ default(), address) when is_binary(address) do
    case Client.get(req, "/parser", [{"address", address}]) do
      {:ok, components} when is_list(components) ->
        canonical = components |> Enum.map(& &1["value"]) |> Enum.join(" ")
        %{query: if(canonical == "", do: address, else: canonical), components: components}

      _ ->
        %{query: address, components: []}
    end
  end
end
