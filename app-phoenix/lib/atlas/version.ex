defmodule Atlas.Version do
  @moduledoc """
  The app's version, without a separate static file to keep in sync:

    * `version/0` — the canonical `mix.exs` version, read from the compiled
      application spec (bump it once per release, where it already lives)
    * `revision/0` — the short git SHA, baked into the release image at build
      time via the `APP_REVISION` build arg (CI passes the commit SHA);
      `nil` in dev/test where no image is involved

  Surfaces: the Settings/admin footers and `GET /api/v1/version`.
  """

  @doc "Canonical version from mix.exs (via the application spec)."
  def version do
    :atlas |> Application.spec(:vsn) |> to_string()
  end

  @doc "Short git SHA of the build, or `nil` outside a release image."
  def revision do
    case System.get_env("APP_REVISION") do
      nil -> nil
      "" -> nil
      sha -> String.slice(sha, 0, 7)
    end
  end

  @doc """
  Human form: `v0.3.0-dev (abc1234)`.
  """
  def display do
    case revision() do
      nil -> "v#{version()}"
      sha -> "v#{version()} (#{sha})"
    end
  end
end
