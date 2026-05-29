# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

db_adapter =
  case System.get_env("ATLAS_DB_ADAPTER") do
    adapter when adapter in ["postgres", "postgresql"] -> Ecto.Adapters.Postgres
    _ -> Ecto.Adapters.SQLite3
  end

config :atlas, Atlas.Repo, adapter: db_adapter

config :atlas,
  ecto_repos: [Atlas.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :atlas, AtlasWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: AtlasWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Atlas.PubSub,
  live_view: [signing_salt: "+lQC8pXJ"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
