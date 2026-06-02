class PruneBeaconEventsJob < ApplicationJob
  queue_as :default

  RETENTION = 90.days

  def perform
    cutoff = Time.current - RETENTION
    deleted = BeaconEvent.where("created_at < ?", cutoff).delete_all
    Rails.logger.info("[chibichange] PruneBeaconEventsJob deleted #{deleted} rows older than #{cutoff.iso8601}")
    deleted
  end
end
