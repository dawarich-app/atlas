class BeaconEvent < ApplicationRecord
  belongs_to :project

  # Append-only. Avoid Rails' automatic updated_at touching.
  self.record_timestamps = false

  # Origin may be empty string (request had no Origin/Referer), but never nil —
  # the DB column is NOT NULL. We accept "" so the dashboard can still surface
  # "anonymous" beacons; nil indicates a programming error.
  validates :origin,  length: { maximum: 200 }
  validate  :origin_must_not_be_nil
  validates :version, presence: true, length: { maximum: 100 }

  before_create { self.created_at ||= Time.current }

  def self.active_origins_within(project, window)
    where(project_id: project.id)
      .where("created_at > ?", window.ago)
      .distinct
      .pluck(:origin)
  end

  private

  def origin_must_not_be_nil
    errors.add(:origin, "can't be nil") if origin.nil?
  end
end
