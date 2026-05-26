defmodule Atlas.Repo do
  use Ecto.Repo,
    otp_app: :atlas,
    adapter: Application.compile_env(:atlas, [Atlas.Repo, :adapter], Ecto.Adapters.SQLite3)

  def adapter do
    case System.get_env("DATABASE_URL") do
      "postgres" <> _ -> Ecto.Adapters.Postgres
      "postgresql" <> _ -> Ecto.Adapters.Postgres
      _ -> Ecto.Adapters.SQLite3
    end
  end
end
