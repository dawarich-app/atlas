defmodule Atlas.Settings do
  @moduledoc """
  Key/value settings store backed by the `settings` table.

  Values are stored as strings; callers serialize/deserialize as needed.
  Keys are normalized to strings, so atom and string keys are interchangeable.
  """

  use Boundary, deps: [Atlas.Repo, Ecto, Ecto.Query], exports: [Setting]

  alias Atlas.Repo
  alias Atlas.Settings.Setting
  import Ecto.Query

  def get(key, default \\ nil) do
    Repo.one(from s in Setting, where: s.key == ^to_string(key), select: s.value) || default
  end

  def set(key, value) do
    %Setting{}
    |> Setting.changeset(%{key: to_string(key), value: value})
    |> Repo.insert(on_conflict: {:replace, [:value, :updated_at]}, conflict_target: :key)
  end

  def unset(key), do: Repo.delete_all(from s in Setting, where: s.key == ^to_string(key))

  @doc """
  Current tiles URL — DB setting wins over `TILES_URL` env var, falling back
  to `""`. Use everywhere the basemap URL is consumed so callers don't
  re-implement the precedence rule.
  """
  def tiles_url, do: get("tiles_url") || System.get_env("TILES_URL") || ""

  @doc """
  Current tiles theme — same precedence as `tiles_url/0`, default `"atlas-light"`.
  """
  def tiles_theme, do: get("tiles_theme") || System.get_env("TILES_THEME") || "atlas-light"
end
