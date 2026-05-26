defmodule Atlas.Maps.Upstream.Placeholder do
  alias Atlas.Maps.Upstream.Client

  def default do
    Client.build(System.get_env("PLACEHOLDER_URL") || "http://localhost:3000",
                 timeout: env_int("PLACEHOLDER_TIMEOUT", 5_000),
                 open_timeout: env_int("PLACEHOLDER_OPEN_TIMEOUT", 2_000))
  end

  def admin_for(req \\ default(), opts) do
    params = [{"text", opts[:text]}] |> maybe_add("lang", opts[:lang])

    case Client.get(req, "/parser/search", params) do
      {:ok, [first | _]} -> extract_admin(first)
      {:ok, _} -> nil
      {:error, _} -> nil
    end
  end

  defp extract_admin(%{"lineage" => [first | _]}) do
    %{
      country: get_in(first, ["country", "name"]),
      state: get_in(first, ["region", "name"]),
      city: get_in(first, ["locality", "name"]),
      county: get_in(first, ["county", "name"]),
      postcode: get_in(first, ["postalcode", "name"])
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp extract_admin(_), do: nil

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, key, val), do: params ++ [{key, val}]

  defp env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      val -> String.to_integer(val)
    end
  end
end
