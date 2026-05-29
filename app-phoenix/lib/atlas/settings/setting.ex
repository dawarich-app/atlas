defmodule Atlas.Settings.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  schema "settings" do
    field :key, :string
    field :value, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(s, attrs) do
    s
    |> cast(attrs, [:key, :value])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
