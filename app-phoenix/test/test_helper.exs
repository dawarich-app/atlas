ExUnit.start()
ExUnit.configure(exclude: [:catalog_artifact])
Ecto.Adapters.SQL.Sandbox.mode(Atlas.Repo, :manual)
# AtlasWeb.GoldenHelper is auto-compiled via elixirc_paths(:test) which
# includes "test/support". No explicit require_file needed.
