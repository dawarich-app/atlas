defmodule Atlas.Control.RegionSelection do
  use Ecto.Schema
  import Ecto.Changeset

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
end
