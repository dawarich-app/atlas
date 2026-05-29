defmodule AtlasWeb.Admin.TilesController do
  @moduledoc """
  JSON endpoint for tile settings. Mirrors Rails
  `Admin::TilesController#update` so the LiveView (and external clients) can
  PATCH/POST `{tiles_url, theme}` and get back the persisted state without a
  full page reload.

  Returns the canonical envelope used elsewhere in M5:

      {"data": {"tiles_url": "...", "theme": "atlas-light", "source": "sidecar"}}
  """

  use AtlasWeb, :controller

  alias Atlas.Settings

  @themes ~w[atlas-light atlas-dark light dark grayscale white black]

  def show(conn, _params) do
    json(conn, %{data: current_state()})
  end

  def update(conn, params) do
    with {:ok, url} <- fetch_url(params),
         {:ok, theme} <- fetch_theme(params) do
      if url, do: Settings.set("tiles_url", url)
      if theme, do: Settings.set("tiles_theme", theme)
      json(conn, %{data: current_state()})
    else
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "BAD_REQUEST", message: reason}})
    end
  end

  defp fetch_url(%{"tiles_url" => url}) when is_binary(url) do
    case String.trim(url) do
      "" -> {:ok, nil}
      trimmed -> {:ok, trimmed}
    end
  end

  defp fetch_url(_), do: {:ok, nil}

  defp fetch_theme(%{"theme" => theme}) when is_binary(theme) do
    if theme in @themes do
      {:ok, theme}
    else
      {:error, "theme must be one of #{Enum.join(@themes, ", ")}"}
    end
  end

  defp fetch_theme(_), do: {:ok, nil}

  defp current_state do
    url = Settings.get("tiles_url") || System.get_env("TILES_URL") || ""
    theme = Settings.get("tiles_theme") || System.get_env("TILES_THEME") || "atlas-light"
    %{tiles_url: url, theme: theme, source: tiles_source(url)}
  end

  @doc """
  Public helper so LiveViews can render the same source-distinction badge.
  """
  def tiles_source(url) when is_binary(url) do
    cond do
      url == "" -> :unset
      String.starts_with?(url, "http://atlas-control") -> :sidecar
      String.contains?(url, "atlas-control:") -> :sidecar
      String.starts_with?(url, "pmtiles://") -> :sidecar
      String.starts_with?(url, "/tiles/") -> :sidecar
      String.starts_with?(url, "http") -> :external
      true -> :external
    end
  end

  def tiles_source(_), do: :unset
end
