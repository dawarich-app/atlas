defmodule Atlas.Repo do
  use Ecto.Repo,
    otp_app: :atlas,
    adapter: Ecto.Adapters.SQLite3
end
