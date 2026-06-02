require "rails_helper"

RSpec.describe "Authors::Versions", type: :request do
  let(:user)    { create(:user) }
  let(:project) { create(:project, user: user) }
  let!(:unreleased) { create(:version, :unreleased, project: project) }

  before { sign_in user, scope: :user }

  describe "PATCH /authors/projects/:slug/versions/:id/release" do
    it "releases the version with number and date" do
      patch release_authors_project_version_path(project, unreleased),
            params: { number: "1.2.0", released_at: "2026-04-30" }

      expect(unreleased.reload).to have_attributes(number: "1.2.0", released_at: Date.new(2026, 4, 30))
      expect(response).to redirect_to(authors_project_path(project))
    end

    it "creates a new Unreleased after a release" do
      patch release_authors_project_version_path(project, unreleased),
            params: { number: "1.2.0", released_at: "2026-04-30" }

      expect(Version.unreleased_for(project)).to be_present
      expect(Version.unreleased_for(project)).not_to eq unreleased
    end

    it "404s when releasing a version on a project the user doesn't own" do
      other_project = create(:project)
      other_v = create(:version, :unreleased, project: other_project)

      patch release_authors_project_version_path(other_project, other_v),
            params: { number: "1.0.0", released_at: "2026-04-30" }
      expect(response).to have_http_status(:not_found)
    end

    it "rejects releasing an already-released version" do
      released = create(:version, project: project, number: "1.0.0", released_at: Date.today)
      patch release_authors_project_version_path(project, released),
            params: { number: "1.1.0", released_at: "2026-04-30" }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /authors/projects/:slug/versions/:id/yank" do
    it "yanks a released version" do
      released = create(:version, project: project, number: "1.0.0", released_at: Date.today)
      patch yank_authors_project_version_path(project, released)
      expect(released.reload.yanked).to eq true
    end

    it "rejects yanking the unreleased version" do
      patch yank_authors_project_version_path(project, unreleased)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
