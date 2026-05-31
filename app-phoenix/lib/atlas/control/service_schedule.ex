defmodule Atlas.Control.ServiceSchedule do
  @moduledoc """
  Cron-expression validation + `services.update_schedule_cron` persistence
  for the auto-update controls.

  Shared between `MapLive` (settings tab) and `AdminServicesLive`.
  """

  alias Atlas.Control.Service
  alias Atlas.Repo

  @doc "Validate a cron expression using Crontab's parser."
  def valid?(expr) when is_binary(expr) do
    case Crontab.CronExpression.Parser.parse(expr) do
      {:ok, _} -> true
      _ -> false
    end
  end

  def valid?(_), do: false

  @doc """
  Persist a cron expression (or `nil` to clear it) onto the matching
  service row. No-op when the service row doesn't exist.
  """
  def persist!(name, cron) do
    case Repo.get_by(Service, name: name) do
      nil -> :ok
      row -> row |> Service.changeset(%{update_schedule_cron: cron}) |> Repo.update!()
    end
  end
end
