module WidgetPayload
  module_function

  # Cap the modal at this many versions so users far behind don't get a
  # firehose. The widget surfaces a "view more releases" link to the public
  # changelog when there's overflow.
  MAX_VERSIONS_SHOWN = 3

  # Returns a Hash payload for the widget endpoint.
  def call(project:, requested_version:)
    released = project.versions
                      .where("released_at IS NOT NULL")
                      .where(yanked: false)
                      .includes(:entries)
                      .order(released_at: :desc, created_at: :desc)
                      .to_a

    latest = released.first
    requested = released.find { |v| v.number == requested_version }

    all_newer =
      if requested
        released.select { |v| v.released_at > requested.released_at }
      else
        # Unknown version — show everything released, but don't claim an update.
        released
      end

    versions_to_show    = all_newer.first(MAX_VERSIONS_SHOWN)
    more_versions_count = all_newer.size - versions_to_show.size

    update_available =
      if requested && latest
        latest.released_at > requested.released_at
      else
        nil
      end

    versions_payload = versions_to_show.map { |v| version_payload(v) }
    all_entries      = versions_to_show.flat_map { |v| v.entries.ordered.to_a }

    {
      project: { slug: project.slug, name: project.name },
      latest_version: latest&.number,
      latest_released_at: latest&.released_at&.iso8601,
      versions: versions_payload,
      counts: all_entries.group_by(&:kind).transform_values(&:size),
      total_entries: all_entries.size,
      update_available: update_available,
      more_versions_count: more_versions_count
    }
  end

  # Build a single version object — entries grouped by Keep-a-Changelog kind
  # in canonical order (Added → Security). Empty kinds are omitted so the
  # widget can iterate keys without checking for empty arrays.
  def version_payload(version)
    grouped = version.entries.ordered.group_by(&:kind)
    entries_by_kind = Entry::KINDS.each_with_object({}) do |kind, h|
      next unless (entries = grouped[kind])&.any?
      h[kind] = entries.flat_map(&:body_tokens)
    end

    {
      number:          version.number,
      released_at:     version.released_at&.iso8601,
      entries_by_kind: entries_by_kind
    }
  end
end
