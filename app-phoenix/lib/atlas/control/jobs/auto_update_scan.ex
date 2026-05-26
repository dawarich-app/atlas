defmodule Atlas.Control.Jobs.AutoUpdateScan do
  @moduledoc """
  Runs every minute via `Oban.Plugins.Cron`. Looks for services with
  `auto_update_enabled = true` whose `update_schedule_cron` matches the
  current minute, and enqueues an `Atlas.Control.Jobs.UpdateService` job
  for each match.

  Services whose `last_update_status` is `"running"` are skipped — the
  per-service uniqueness constraint on `UpdateService` enforces this at
  Oban-insert time too, but filtering early saves a round-trip.
  """

  use Oban.Worker, queue: :control, unique: [period: 60]

  import Ecto.Query

  alias Atlas.{Repo, Control.Service}
  alias Crontab.CronExpression.Parser
  alias Crontab.DateChecker

  @impl Oban.Worker
  def perform(_job) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Service
    |> where([s], s.auto_update_enabled == true)
    |> where([s], is_nil(s.last_update_status) or s.last_update_status != "running")
    |> Repo.all()
    |> Enum.filter(fn s -> matches_now?(s.update_schedule_cron, now) end)
    |> Enum.each(fn s ->
      %{name: s.name}
      |> Atlas.Control.Jobs.UpdateService.new()
      |> Oban.insert()
    end)

    :ok
  end

  defp matches_now?(nil, _now), do: false

  defp matches_now?(cron, now) do
    case Parser.parse(cron) do
      {:ok, exp} -> DateChecker.matches_date?(exp, now)
      _ -> false
    end
  end
end
