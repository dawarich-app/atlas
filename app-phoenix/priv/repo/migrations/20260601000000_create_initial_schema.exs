defmodule Atlas.Repo.Migrations.CreateInitialSchema do
  use Ecto.Migration

  def change do
    create table(:services) do
      add :name, :string, null: false
      add :profile, :string, null: false
      add :enabled, :boolean, null: false, default: false
      add :status, :integer, null: false, default: 0
      add :phase, :string
      add :progress, :float
      add :last_log, :text
      add :last_error, :text
      add :disk_bytes, :bigint, null: false, default: 0
      add :last_seen_at, :utc_datetime
      add :auto_update_enabled, :boolean, null: false, default: false
      add :update_schedule_cron, :string
      add :dataset_updated_at, :utc_datetime
      add :last_update_check_at, :utc_datetime
      add :last_update_status, :string
      add :last_update_error, :text
      add :last_update_duration_s, :integer
      add :pinned_image_tag, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:services, [:name])
    create index(:services, [:enabled])
    create index(:services, [:auto_update_enabled])
    create index(:services, [:last_update_status])

    create table(:region_selections) do
      add :region_name, :string, null: false
      add :active, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0
      add :orphaned, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:region_selections, [:region_name])

    create table(:settings) do
      add :key, :string
      add :value, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:settings, [:key])
  end
end
