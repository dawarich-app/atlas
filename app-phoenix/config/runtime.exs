import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/atlas start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :atlas, AtlasWeb.Endpoint, server: true
end

config :atlas, AtlasWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url = System.get_env("DATABASE_URL")

  if is_binary(database_url) and
       (String.starts_with?(database_url, "postgres://") or
          String.starts_with?(database_url, "postgresql://")) and
       Atlas.Repo.__adapter__() != Ecto.Adapters.Postgres do
    raise """
    DATABASE_URL points to Postgres, but the release was built with the SQLite3 adapter.

    Rebuild with `ATLAS_DB_ADAPTER=postgres MIX_ENV=prod mix release` to enable
    Postgres support, or unset DATABASE_URL to use SQLite.
    """
  end

  database_config =
    case database_url do
      url when is_binary(url) and (binary_part(url, 0, 8) == "postgres" or binary_part(url, 0, 10) == "postgresql") ->
        [url: url, pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")]

      _ ->
        [
          database: System.get_env("DATABASE_PATH") || "/data/atlas.sqlite3",
          pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
          journal_mode: :wal,
          cache_size: -64_000,
          temp_store: :memory
        ]
    end

  config :atlas, Atlas.Repo, database_config

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :atlas, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :atlas, AtlasWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :atlas, AtlasWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :atlas, AtlasWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
