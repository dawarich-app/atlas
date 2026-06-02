json.slug         @project.slug
json.name         @project.name
json.description  @project.description
json.homepage_url @project.homepage_url

json.versions @versions do |version|
  json.number      version.number
  json.released_at version.released_at&.iso8601
  json.yanked      version.yanked?
  json.entries version.entries.ordered do |entry|
    json.kind          entry.kind
    json.body_markdown entry.body_markdown
    json.body_tokens   entry.body_tokens
  end
end
