require "rails_helper"

RSpec.describe "Widget rate limiting", type: :request do
  let!(:project) { create(:project, slug: "dawarich") }

  before do
    Rails.cache.clear
    create(:version, project: project, number: "1.0.0", released_at: Date.today)
    Rack::Attack.enabled = true
  end

  after { Rack::Attack.enabled = false }

  it "allows up to 60 requests per origin per minute" do
    60.times do
      get widget_payload_path(slug: "dawarich", v: "1"),
          headers: { "HTTP_ORIGIN" => "https://burst.example.com" }
      expect(response).to have_http_status(:ok)
    end
  end

  it "returns 429 on the 61st request from the same origin within a minute" do
    61.times do |i|
      get widget_payload_path(slug: "dawarich", v: "1"),
          headers: { "HTTP_ORIGIN" => "https://burst.example.com" }
      if i == 60
        expect(response).to have_http_status(:too_many_requests)
        expect(response.headers["Retry-After"]).to be_present
      end
    end
  end

  it "tracks separate buckets per origin" do
    61.times do
      get widget_payload_path(slug: "dawarich", v: "1"),
          headers: { "HTTP_ORIGIN" => "https://noisy.example.com" }
    end
    # Different origin still allowed
    get widget_payload_path(slug: "dawarich", v: "1"),
        headers: { "HTTP_ORIGIN" => "https://other.example.com" }
    expect(response).to have_http_status(:ok)
  end
end
