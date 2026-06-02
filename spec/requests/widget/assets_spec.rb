require "rails_helper"

RSpec.describe "Widget::Assets", type: :request do
  describe "GET /w/v1/loader.js" do
    it "returns 200 with javascript content-type" do
      get widget_loader_path
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq "application/javascript"
    end

    it "sets short caching headers (5min fresh, 1min stale-while-revalidate)" do
      get widget_loader_path
      expect(response.headers["Cache-Control"]).to include("public", "max-age=300", "stale-while-revalidate=60")
      expect(response.headers["Cache-Control"]).not_to include("86400")
    end

    it "supports conditional GET — second request with matching ETag returns 304" do
      get widget_loader_path
      expect(response).to have_http_status(:ok)
      etag = response.headers["ETag"]
      last_modified = response.headers["Last-Modified"]
      expect(etag).to be_present
      expect(last_modified).to be_present

      get widget_loader_path,
          headers: { "HTTP_IF_NONE_MATCH" => etag, "HTTP_IF_MODIFIED_SINCE" => last_modified }
      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_blank
    end

    it "sets X-Content-Type-Options: nosniff" do
      get widget_loader_path
      expect(response.headers["X-Content-Type-Options"]).to eq "nosniff"
    end

    it "responds 404 if the bundle file is missing" do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(/widget\.v1\.js\z/).and_return(false)
      get widget_loader_path
      expect(response).to have_http_status(:not_found)
    end
  end
end
