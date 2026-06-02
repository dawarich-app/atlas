class InstanceMetrics
  Result = Struct.new(:active_30d, :version_distribution_30d, :daily_30d, keyword_init: true)

  WINDOW = 30.days

  def self.for(project)
    new(project).result
  end

  def initialize(project)
    @project = project
    @now = Time.current
  end

  def result
    Result.new(
      active_30d:               distinct_origin_count,
      version_distribution_30d: version_distribution,
      daily_30d:                daily_series
    )
  end

  private

  attr_reader :project, :now

  def scope
    BeaconEvent.where(project_id: project.id).where("created_at > ?", now - WINDOW)
  end

  def distinct_origin_count
    scope.where.not(origin: "").distinct.count(:origin)
  end

  # Returns [{ version: "2.0", count: 14 }, ...] using each origin's most-recent version.
  def version_distribution
    rows = scope.where.not(origin: "").select(:origin, :version, :created_at).order(created_at: :desc).to_a
    seen = {}
    rows.each do |row|
      seen[row.origin] ||= row.version
    end
    seen.values.tally.map { |version, count| { version: version, count: count } }
                     .sort_by { |h| -h[:count] }
  end

  # Daily distinct-origin counts for the last 30 days.
  # Returns [] when there are no beacons in the window.
  def daily_series
    rows = scope.where.not(origin: "")
                .group("date_trunc('day', created_at)")
                .distinct.count(:origin)
    return [] if rows.empty?

    by_date = rows.each_with_object({}) { |(k, v), h| h[k.to_date] = v }

    (0...30).map do |i|
      day = (now - i.days).to_date
      { date: day, active: by_date[day] || 0 }
    end.reverse
  end
end
