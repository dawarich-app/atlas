require "rails_helper"

RSpec.describe "Public::Changelogs", type: :request do
  let(:project) { create(:project, slug: "dawarich", name: "Dawarich") }

  before do
    v1 = create(:version, project: project, number: "1.0.0", released_at: Date.new(2025, 1, 1))
    v2 = create(:version, project: project, number: "2.0.0", released_at: Date.new(2026, 4, 1))
    yk = create(:version, :yanked, project: project, number: "1.5.0", released_at: Date.new(2025, 6, 1))
    create(:version, :unreleased, project: project)

    create(:entry, version: v1, kind: "added", body_markdown: "Initial release", position: 0,
                   body_tokens: [{ "t" => "p", "c" => [{ "t" => "text", "v" => "Initial release" }] }])
    create(:entry, version: v2, kind: "added", body_markdown: "**Big** new feature", position: 0,
                   body_tokens: [{ "t" => "p", "c" => [
                     { "t" => "strong", "c" => [{ "t" => "text", "v" => "Big" }] },
                     { "t" => "text", "v" => " new feature" }
                   ]}])
    create(:entry, version: v2, kind: "fixed", body_markdown: "edge case", position: 1,
                   body_tokens: [{ "t" => "p", "c" => [{ "t" => "text", "v" => "edge case" }] }])
    create(:entry, version: yk, kind: "added", body_markdown: "broken thing", position: 0,
                   body_tokens: [{ "t" => "p", "c" => [{ "t" => "text", "v" => "broken thing" }] }])
  end

  describe "GET /c/:slug" do
    it "returns 200 and shows the project name" do
      get public_changelog_path(slug: "dawarich")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dawarich")
    end

    it "renders versions in reverse chronological order" do
      get public_changelog_path(slug: "dawarich")
      idx_2 = response.body.index("2.0.0")
      idx_15 = response.body.index("1.5.0")
      idx_1 = response.body.index("1.0.0")
      expect([idx_2, idx_15, idx_1]).to all(be_present)
      expect(idx_2).to be < idx_15
      expect(idx_15).to be < idx_1
    end

    it "marks yanked versions visually" do
      get public_changelog_path(slug: "dawarich")
      expect(response.body).to match(/1\.5\.0.*?YANKED/m)
    end

    it "renders strong tags from tokens (not raw markdown)" do
      get public_changelog_path(slug: "dawarich")
      expect(response.body).to include("<strong>Big</strong>")
      expect(response.body).not_to include("**Big**")
    end

    it "skips the empty Unreleased section if no entries" do
      get public_changelog_path(slug: "dawarich")
      expect(response.body).not_to include("Unreleased")
    end

    it "404s for unknown slug" do
      get public_changelog_path(slug: "nonexistent")
      expect(response).to have_http_status(:not_found)
    end

    it "responds 304 Not Modified when If-Modified-Since matches Last-Modified" do
      get public_changelog_path(slug: "dawarich")
      expect(response).to have_http_status(:ok)
      last_modified = response.headers["Last-Modified"]
      etag          = response.headers["ETag"]
      expect(last_modified).to be_present
      expect(etag).to be_present

      get public_changelog_path(slug: "dawarich"),
          headers: { "HTTP_IF_MODIFIED_SINCE" => last_modified, "HTTP_IF_NONE_MATCH" => etag }
      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_blank
    end
  end

  describe "GET /c/:slug.json" do
    it "returns the changelog as JSON" do
      get public_changelog_path(slug: "dawarich", format: :json)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json).to include("slug" => "dawarich", "name" => "Dawarich")
      expect(json["versions"]).to be_an(Array)
      v2 = json["versions"].find { _1["number"] == "2.0.0" }
      expect(v2["yanked"]).to eq false
      expect(v2["entries"].size).to eq 2
    end
  end

  describe "GET /c/:slug.rss" do
    it "returns an RSS 2.0 feed of releases" do
      get public_changelog_path(slug: "dawarich", format: :rss)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq "application/rss+xml"

      body = response.body
      expect(body).to include("<rss version=\"2.0\"")
      expect(body).to include("<title>Dawarich — Changelog</title>")
      expect(body).to include("2.0.0")
      expect(body).to include("1.5.0")
      expect(body).to include("[YANKED]")
      expect(body).to include("1.0.0")
    end
  end
end
