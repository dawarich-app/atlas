defmodule Atlas.Control.RegionSelection do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Atlas.Repo

  schema "region_selections" do
    field :region_name, :string
    field :active, :boolean, default: true
    field :position, :integer, default: 0
    field :orphaned, :boolean, default: false
    timestamps(type: :utc_datetime)
  end

  def changeset(rs, attrs) do
    rs
    |> cast(attrs, [:region_name, :active, :position, :orphaned])
    |> validate_required([:region_name])
    |> unique_constraint(:region_name)
  end

  @doc """
  Toggle a region's selection state. Removes the row when toggling off,
  inserts at the next position when toggling on for the first time, or
  flips `active: false → true` when a previously-active row is being
  re-selected.
  """
  def toggle(name) when is_binary(name) do
    case Repo.all(from r in __MODULE__, where: r.region_name == ^name) do
      [%__MODULE__{active: true} | _] ->
        Repo.delete_all(from r in __MODULE__, where: r.region_name == ^name)

      [%__MODULE__{active: false} = row | _] ->
        row |> changeset(%{active: true}) |> Repo.update!()

      [] ->
        %__MODULE__{}
        |> changeset(%{region_name: name, active: true, position: next_position()})
        |> Repo.insert!()
    end
  end

  @doc "List active region names in display order."
  def active_names do
    __MODULE__
    |> where(active: true)
    |> order_by(:position)
    |> Repo.all()
    |> Enum.map(& &1.region_name)
  end

  defp next_position do
    case Repo.aggregate(__MODULE__, :max, :position) do
      nil -> 0
      n -> n + 1
    end
  end
end
