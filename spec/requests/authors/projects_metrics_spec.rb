require "rails_helper"

RSpec.describe "Authors::Projects show with metrics", type: :request do
  let(:user)    { create(:user) }
  let(:project) { create(:project, user: user) }

  before { sign_in user, scope: :user }

  it "shows zero metrics for a brand-new project" do
    get authors_project_path(project)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("0", "active instances (30d)")
  end

  it "shows aggregated metrics when beacons exist" do
    create(:beacon_event, project: project, origin: "https://a.example", version: "1.0", created_at: 1.day.ago)
    create(:beacon_event, project: project, origin: "https://b.example", version: "1.0", created_at: 1.day.ago)

    get authors_project_path(project)
    expect(response.body).to include("2", "active instances (30d)")
    expect(response.body).to include("1.0")
  end
end
