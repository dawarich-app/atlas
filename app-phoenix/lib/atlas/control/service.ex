defmodule Atlas.Control.Service do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [
    unknown: 0,
    stopped: 1,
    starting: 2,
    downloading: 3,
    building: 4,
    ready: 5,
    error: 6,
    unhealthy: 7
  ]
  @update_statuses ~w[running success failure]

  schema "services" do
    field :name, :string
    field :profile, :string
    field :enabled, :boolean, default: false
    field :status, Ecto.Enum, values: @statuses, default: :unknown
    field :phase, :string
    field :progress, :float
    field :last_log, :string
    field :last_error, :string
    field :disk_bytes, :integer, default: 0
    field :last_seen_at, :utc_datetime
    field :auto_update_enabled, :boolean, default: false
    field :update_schedule_cron, :string
    field :dataset_updated_at, :utc_datetime
    field :last_update_check_at, :utc_datetime
    field :last_update_status, :string
    field :last_update_error, :string
    field :last_update_duration_s, :integer
    field :pinned_image_tag, :string
    timestamps(type: :utc_datetime)
  end

  @castable ~w[
    name profile enabled status phase progress last_log last_error disk_bytes
    last_seen_at auto_update_enabled update_schedule_cron dataset_updated_at
    last_update_check_at last_update_status last_update_error last_update_duration_s
    pinned_image_tag
  ]a

  def changeset(service, attrs) do
    service
    |> cast(attrs, @castable)
    |> validate_required([:name, :profile])
    |> unique_constraint(:name)
    |> validate_number(:progress, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:disk_bytes, greater_than_or_equal_to: 0)
    |> validate_inclusion(:last_update_status, @update_statuses)
  end

  def statuses, do: @statuses
  def update_statuses, do: @update_statuses
end
