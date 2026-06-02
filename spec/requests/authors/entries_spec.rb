require "rails_helper"

RSpec.describe "Authors::Entries", type: :request do
  let(:user)        { create(:user) }
  let(:project)     { create(:project, user: user) }
  let!(:unreleased) { create(:version, :unreleased, project: project) }

  before { sign_in user, scope: :user }

  describe "POST /authors/projects/:slug/entries" do
    it "creates an entry on the Unreleased version" do
      expect {
        post authors_project_entries_path(project),
             params: { entry: { kind: "added", body_markdown: "Added **search**" } }
      }.to change(unreleased.entries, :count).by(1)

      entry = unreleased.entries.last
      expect(entry).to have_attributes(kind: "added", body_markdown: "Added **search**")
      expect(entry.body_tokens).to be_an(Array).and(be_present)
      expect(entry.body_tokens.first.dig("c", 1, "t")).to eq("strong")
    end

    it "rejects an unknown kind" do
      post authors_project_entries_path(project),
           params: { entry: { kind: "feature", body_markdown: "x" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404s when project belongs to another user" do
      other_project = create(:project)
      create(:version, :unreleased, project: other_project)
      post authors_project_entries_path(other_project),
           params: { entry: { kind: "added", body_markdown: "x" } }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /authors/projects/:slug/entries/:id" do
    let(:entry) { create(:entry, version: unreleased, body_markdown: "old") }

    it "updates body_markdown and re-tokenizes" do
      patch authors_project_entry_path(project, entry),
            params: { entry: { body_markdown: "**new**" } }

      expect(entry.reload.body_markdown).to eq "**new**"
      expect(entry.body_tokens.first.dig("c", 0, "t")).to eq("strong")
    end

    it "404s for entries not under one of your projects" do
      other_entry = create(:entry)
      patch authors_project_entry_path(project, other_entry),
            params: { entry: { body_markdown: "x" } }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /authors/projects/:slug/entries/:id" do
    it "deletes the entry" do
      entry = create(:entry, version: unreleased)
      expect {
        delete authors_project_entry_path(project, entry)
      }.to change(unreleased.entries, :count).by(-1)
    end

    it "rejects deleting an entry on a released version" do
      released = create(:version, project: project, number: "1.0.0", released_at: Date.today)
      entry = create(:entry, version: released)
      delete authors_project_entry_path(project, entry)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
