released = @versions.reject(&:unreleased?)

xml.instruct! :xml, version: "1.0"
xml.rss(version: "2.0") do
  xml.channel do
    xml.title "#{@project.name} — Changelog"
    xml.link  public_changelog_url(slug: @project.slug)
    xml.description (@project.description.presence || "Changelog for #{@project.name}.")

    released.each do |version|
      xml.item do
        title = version.yanked? ? "#{version.number} [YANKED]" : version.number
        xml.title title
        xml.link  "#{public_changelog_url(slug: @project.slug)}#v-#{version.number.parameterize}"
        xml.guid  "v-#{version.id}", isPermaLink: false
        xml.pubDate version.released_at.to_time.utc.rfc822 if version.released_at

        description_html = version.entries.by_kind.map do |kind, group|
          items = group.map { |e| "<li>#{render_tokens_to_html(e.body_tokens)}</li>" }.join
          "<h3>#{ERB::Util.html_escape(kind.titleize)}</h3><ul>#{items}</ul>"
        end.join

        xml.description description_html
      end
    end
  end
end
