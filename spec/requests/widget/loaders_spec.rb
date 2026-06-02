require "rails_helper"

RSpec.describe "Widget::Loaders", type: :request do
  let(:project) { create(:project, slug: "dawarich", name: "Dawarich") }

  before do
    v = create(:version, project: project, number: "2.0.0", released_at: Date.new(2026, 4, 1))
    create(:entry, version: v, kind: "added", body_markdown: "thing",
           body_tokens: [{ "t" => "p", "c" => [{ "t" => "text", "v" => "thing" }] }])
  end

  describe "GET /w/v1/:slug.json" do
    it "returns the payload as JSON" do
      get widget_payload_path(slug: "dawarich", v: "1.0.0"),
          headers: { "HTTP_ORIGIN" => "https://my.dawarich.app" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq "application/json"
      json = JSON.parse(response.body)
      expect(json).to include("project", "latest_version", "versions", "total_entries")
      expect(json["project"]).to eq("slug" => "dawarich", "name" => "Dawarich")
    end

    it "records a BeaconEvent with origin, version, and project_id" do
      expect {
        get widget_payload_path(slug: "dawarich", v: "1.2.3"),
            headers: { "HTTP_ORIGIN" => "https://my.dawarich.app" }
      }.to change(BeaconEvent, :count).by(1)

      event = BeaconEvent.last
      expect(event).to have_attributes(
        project_id: project.id,
        origin:     "https://my.dawarich.app",
        version:    "1.2.3"
      )
    end

    it "stores the version as 'unknown' when the v= parameter is missing" do
      get widget_payload_path(slug: "dawarich"),
          headers: { "HTTP_ORIGIN" => "https://my.dawarich.app" }
      expect(BeaconEvent.last.version).to eq "unknown"
    end

    it "still records a beacon when origin is missing (origin = '')" do
      expect {
        get widget_payload_path(slug: "dawarich", v: "1.0.0")
      }.to change(BeaconEvent, :count).by(1)
      expect(BeaconEvent.last.origin).to eq ""
    end

    it "sets Cache-Control: no-store" do
      get widget_payload_path(slug: "dawarich", v: "1.0.0"),
          headers: { "HTTP_ORIGIN" => "https://my.dawarich.app" }
      expect(response.headers["Cache-Control"]).to include("no-store")
    end

    it "sets Access-Control-Allow-Origin: *" do
      get widget_payload_path(slug: "dawarich", v: "1.0.0"),
          headers: { "HTTP_ORIGIN" => "https://my.dawarich.app" }
      expect(response.headers["Access-Control-Allow-Origin"]).to eq "*"
    end

    it "returns {} with 404 for an unknown slug" do
      get widget_payload_path(slug: "nonexistent")
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "is case-insensitive on slug lookup" do
      get widget_payload_path(slug: "DAWARICH"),
          headers: { "HTTP_ORIGIN" => "https://my.dawarich.app" }
      expect(response).to have_http_status(:ok)
    end

    it "still serves the payload when the beacon write raises (e.g. DB error)" do
      # Simulate an infrastructure-level failure on the beacon insert:
      # a dropped connection, statement timeout, or constraint hiccup must
      # not propagate to the user-facing widget response.
      allow(BeaconEvent).to receive(:create!).and_raise(ActiveRecord::StatementInvalid.new("simulated"))

      get widget_payload_path(slug: "dawarich", v: "1.0.0"),
          headers: { "HTTP_ORIGIN" => "https://my.dawarich.app" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["project"]).to eq("slug" => "dawarich", "name" => "Dawarich")
    end
  end
end
