defmodule Atlas.Repo do
  use Ecto.Repo,
    otp_app: :atlas,
    adapter: Application.compile_env(:atlas, [Atlas.Repo, :adapter], Ecto.Adapters.SQLite3)

  @doc """
  Returns the compiled-in adapter module. Adapter selection happens at
  BUILD time via the `ATLAS_DB_ADAPTER` env var (set to `postgres` to use
  `Ecto.Adapters.Postgres`; defaults to `Ecto.Adapters.SQLite3`).

  The runtime `DATABASE_URL` only configures the connection string, NOT
  the adapter module. To use Postgres, rebuild with:

      ATLAS_DB_ADAPTER=postgres MIX_ENV=prod mix release
  """
  def adapter, do: __adapter__()
end
