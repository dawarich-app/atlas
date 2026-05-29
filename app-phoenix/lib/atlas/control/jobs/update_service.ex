defmodule Atlas.Control.Jobs.UpdateService do
  @moduledoc """
  Performs a `docker compose pull` for one service and records the outcome.

  Uniqueness:

      unique: [period: :infinity, states: [:available, :scheduled, :executing],
               fields: [:args]]

  prevents two simultaneous updates for the same service. On failure we flip
  `auto_update_enabled` to `false` — a kill switch to stop runaway retries.
  """

  use Oban.Worker,
    queue: :control,
    unique: [period: :infinity, states: [:available, :scheduled, :executing], fields: [:args]]

  alias Atlas.{Repo, Control.Service, Control.DockerCompose}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"name" => name}}) do
    started = DateTime.utc_now()

    case begin_update!(name) do
      :ok ->
        case DockerCompose.update(name, :pull) do
          {0, _output} ->
            finish_update!(name, success: true, duration_s: elapsed_s(started))
            :ok

          {_code, output} ->
            finish_update!(name,
              success: false,
              duration_s: elapsed_s(started),
              error: output
            )

            {:error, :update_failed}
        end

      :busy ->
        {:cancel, :already_running}

      :not_found ->
        {:cancel, :service_not_found}
    end
  end

  defp begin_update!(name) do
    Repo.transaction(fn ->
      case Repo.get_by(Service, name: name) do
        nil ->
          :not_found

        %Service{last_update_status: "running"} ->
          :busy

        %Service{} = service ->
          service
          |> Service.changeset(%{
            last_update_check_at: DateTime.utc_now() |> DateTime.truncate(:second),
            last_update_status: "running",
            last_update_error: nil
          })
          |> Repo.update!()

          :ok
      end
    end)
    |> elem(1)
  end

  defp finish_update!(name, opts) do
    service = Repo.get_by!(Service, name: name)

    attrs =
      if Keyword.get(opts, :success, false) do
        %{
          last_update_status: "success",
          last_update_duration_s: Keyword.get(opts, :duration_s),
          last_update_error: nil,
          dataset_updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      else
        %{
          last_update_status: "failure",
          last_update_duration_s: Keyword.get(opts, :duration_s),
          last_update_error: String.slice(to_string(Keyword.get(opts, :error, "")), 0, 2000),
          auto_update_enabled: false
        }
      end

    service
    |> Service.changeset(attrs)
    |> Repo.update!()
  end

  defp elapsed_s(started), do: DateTime.diff(DateTime.utc_now(), started)
end
