require "rails_helper"

RSpec.describe "Authors::Projects show — embed snippet", type: :request do
  let(:user)    { create(:user) }
  let(:project) { create(:project, user: user, slug: "dawarich") }

  before { sign_in user, scope: :user }

  it "renders the embed snippet with the project's slug" do
    get authors_project_path(project)
    # The snippet is rendered inside <pre> as literal text, so quotes are HTML-escaped.
    expect(response.body).to include('data-slug=&quot;dawarich&quot;')
    expect(response.body).to include("/w/v1/loader.js")
  end

  it "uses the configured widget host" do
    Rails.application.config.x.widget_host = "https://example.test"
    get authors_project_path(project)
    expect(response.body).to include("https://example.test/w/v1/loader.js")
  ensure
    Rails.application.config.x.widget_host = "http://localhost:3000"
  end
end
