defmodule Atlas.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  import Cachex.Spec, only: [expiration: 1]

  @impl true
  def start(_type, _args) do
    children =
      [
        AtlasWeb.Telemetry,
        Atlas.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:atlas, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:atlas, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Atlas.PubSub},
        {Cachex,
         name: :reverse_cache, expiration: expiration(default: :timer.minutes(60))}
      ] ++ control_children() ++ [AtlasWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Atlas.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        if control_supervisor_autostart?(), do: Atlas.Control.Supervisor.post_start()
        {:ok, pid}

      err ->
        err
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AtlasWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end

  defp control_supervisor_autostart? do
    Application.get_env(:atlas, :control_supervisor_autostart, true)
  end

  defp control_children do
    if control_supervisor_autostart?() do
      [{Oban, Application.fetch_env!(:atlas, Oban)}, Atlas.Control.Supervisor]
    else
      []
    end
  end
end
