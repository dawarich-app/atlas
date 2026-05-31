defmodule AtlasWeb.Admin.RegionsController do
  @moduledoc """
  JSON endpoint for region selection. Mirrors Rails
  `Admin::RegionsController#update`. Accepts a list of region names and
  persists them, replacing the existing selection. Broadcasts a
  `{:regions_changed, names}` event on the `\"admin:regions\"` PubSub topic
  so LiveViews can react.
  """

  use AtlasWeb, :controller

  import Ecto.Query

  alias Atlas.Repo
  alias Atlas.Control.{RegionCatalog, RegionSelection}

  def show(conn, _params) do
    json(conn, %{data: current_state()})
  end

  def update(conn, params) do
    with {:ok, names} <- fetch_selected(params),
         :ok <- persist!(names) do
      broadcast_selection_change(names)
      json(conn, %{data: current_state()})
    else
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "BAD_REQUEST", message: reason}})
    end
  end

  defp fetch_selected(%{"selected" => names}) when is_list(names) do
    cleaned =
      names
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {:ok, cleaned}
  end

  defp fetch_selected(_), do: {:error, "selected must be a list of region names"}

  defp persist!(names) do
    Repo.transaction(fn ->
      Repo.delete_all(RegionSelection)

      names
      |> Enum.with_index()
      |> Enum.each(fn {name, idx} ->
        %RegionSelection{}
        |> RegionSelection.changeset(%{
          region_name: name,
          position: idx,
          active: true
        })
        |> Repo.insert!()
      end)
    end)

    :ok
  end

  defp current_state do
    selected =
      RegionSelection
      |> where(active: true)
      |> order_by(:position)
      |> Repo.all()
      |> Enum.map(& &1.region_name)

    available = RegionCatalog.all() |> Enum.map(& &1.name)
    %{selected: selected, available: available}
  end

  @doc """
  Broadcast a region-selection change to all subscribers of `\"admin:regions\"`.
  Used by both the JSON endpoint and the LiveView so cross-tab updates work.
  """
  def broadcast_selection_change(names) when is_list(names) do
    Phoenix.PubSub.broadcast(Atlas.PubSub, "admin:regions", {:regions_changed, names})
  end
end
