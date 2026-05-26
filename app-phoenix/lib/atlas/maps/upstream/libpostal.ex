defmodule Atlas.Maps.Upstream.Libpostal do
  alias Atlas.Maps.Upstream.Client

  def default do
    Client.build(System.get_env("LIBPOSTAL_URL") || "http://localhost:8080",
                 timeout: env_int("LIBPOSTAL_TIMEOUT", 5_000),
                 open_timeout: env_int("LIBPOSTAL_OPEN_TIMEOUT", 2_000))
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

  defp env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      val -> String.to_integer(val)
    end
  end
end
