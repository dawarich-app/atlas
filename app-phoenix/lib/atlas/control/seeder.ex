defmodule Atlas.Control.Seeder do
  @moduledoc """
  Boot-time seeding for the 7 known upstream services.

  Idempotent on both layers:

    * `Repo.insert_all/3` uses `ON CONFLICT (name) DO NOTHING`, so re-running
      doesn't create duplicate rows.
    * `ServiceSupervisor.start_service/3` is wrapped to ignore the
      `{:already_started, pid}` race when a process for the same name is
      already registered.
  """

  alias Atlas.Repo
  alias Atlas.Control.{Service, ServiceSupervisor}
  alias Atlas.Control.Parsers

  @services [
    %{name: "photon", profile: "geocoding", parser: Parsers.Photon},
    %{name: "placeholder", profile: "geocoding", parser: Parsers.Placeholder},
    %{name: "libpostal", profile: "geocoding", parser: Parsers.Libpostal},
    %{name: "valhalla", profile: "routing", parser: Parsers.Valhalla},
    %{name: "overpass", profile: "pois", parser: Parsers.Overpass},
    %{name: "otp", profile: "transit", parser: Parsers.OTP},
    %{name: "whosonfirst", profile: "data-setup", parser: Parsers.Whosonfirst}
  ]

  @doc """
  Insert service rows (idempotent via `ON CONFLICT`) and start a ServiceState
  per service. Safe to call multiple times.
  """
  def seed_and_start! do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(@services, fn s ->
        %{name: s.name, profile: s.profile, inserted_at: now, updated_at: now}
      end)

    Repo.insert_all(Service, rows, on_conflict: :nothing, conflict_target: :name)

    Enum.each(@services, fn s ->
      case ServiceSupervisor.start_service(s.name, s.profile, s.parser) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    end)

    :ok
  end

  @doc "List the known service definitions."
  def known_services, do: @services
end
