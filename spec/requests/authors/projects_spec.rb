require "rails_helper"

RSpec.describe "Authors::Projects", type: :request do
  let(:user)  { create(:user) }
  let(:other) { create(:user) }

  describe "GET /authors/projects" do
    it "redirects to sign-in when not authenticated" do
      get authors_projects_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "lists only the current user's projects" do
      sign_in user
      mine = create(:project, user: user, name: "Mine")
      create(:project, user: other, name: "Theirs")

      get authors_projects_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mine")
      expect(response.body).not_to include("Theirs")
    end
  end

  describe "POST /authors/projects" do
    before { sign_in user }

    it "creates a project" do
      expect {
        post authors_projects_path, params: { project: { slug: "dawarich", name: "Dawarich" } }
      }.to change(user.projects, :count).by(1)

      expect(response).to redirect_to(authors_project_path("dawarich"))
    end

    it "creates an Unreleased version automatically" do
      post authors_projects_path, params: { project: { slug: "dawarich", name: "Dawarich" } }

      project = user.projects.find_by!(slug: "dawarich")
      expect(Version.unreleased_for(project)).to be_present
      expect(Version.unreleased_for(project).number).to eq "Unreleased"
    end

    it "rejects an invalid slug" do
      post authors_projects_path, params: { project: { slug: "BAD!", name: "Bad" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /authors/projects/:slug" do
    before { sign_in user }

    it "shows the project to its owner" do
      project = create(:project, user: user, slug: "dawarich")
      get authors_project_path(project)
      expect(response).to have_http_status(:ok)
    end

    it "404s when slug doesn't belong to the current user" do
      create(:project, user: other, slug: "stolen")
      get authors_project_path("stolen")
      expect(response).to have_http_status(:not_found)
    end
  end
end
