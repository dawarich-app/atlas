require "rails_helper"

RSpec.describe OriginNormalizer do
  def call_with(headers)
    request = ActionDispatch::Request.new("HTTP_HOST" => "app.chibichange.com").tap do |r|
      headers.each { |k, v| r.set_header(k, v) }
    end
    described_class.call(request)
  end

  describe ".call" do
    it "returns the Origin when present" do
      result = call_with("HTTP_ORIGIN" => "https://my.dawarich.app")
      expect(result).to eq "https://my.dawarich.app"
    end

    it "falls back to Referer when Origin is absent" do
      result = call_with("HTTP_REFERER" => "https://my.dawarich.app/admin/dashboard?x=1")
      expect(result).to eq "https://my.dawarich.app"
    end

    it "prefers Origin over Referer" do
      result = call_with(
        "HTTP_ORIGIN"  => "https://origin.example.com",
        "HTTP_REFERER" => "https://referer.example.com/path"
      )
      expect(result).to eq "https://origin.example.com"
    end

    it "returns nil when neither header is present" do
      result = call_with({})
      expect(result).to be_nil
    end

    it "lowercases the host" do
      result = call_with("HTTP_ORIGIN" => "https://MY.Dawarich.App")
      expect(result).to eq "https://my.dawarich.app"
    end

    it "preserves explicit non-default port" do
      result = call_with("HTTP_ORIGIN" => "https://my.dawarich.app:8443")
      expect(result).to eq "https://my.dawarich.app:8443"
    end

    it "drops default port for the scheme" do
      result = call_with("HTTP_ORIGIN" => "https://my.dawarich.app:443")
      expect(result).to eq "https://my.dawarich.app"
      result = call_with("HTTP_ORIGIN" => "http://my.dawarich.app:80")
      expect(result).to eq "http://my.dawarich.app"
    end

    it "treats http and https as different origins" do
      a = call_with("HTTP_ORIGIN" => "http://my.dawarich.app")
      b = call_with("HTTP_ORIGIN" => "https://my.dawarich.app")
      expect(a).not_to eq b
    end

    it "does NOT strip www. (treats as a distinct origin)" do
      a = call_with("HTTP_ORIGIN" => "https://my.dawarich.app")
      b = call_with("HTTP_ORIGIN" => "https://www.dawarich.app")
      expect(a).not_to eq b
    end

    it "rejects malformed origin (returns nil)" do
      result = call_with("HTTP_ORIGIN" => "not a url")
      expect(result).to be_nil
    end

    it "rejects scheme other than http/https" do
      result = call_with("HTTP_ORIGIN" => "javascript://example.com")
      expect(result).to be_nil
    end

    it "drops query, fragment, and path from Referer" do
      result = call_with("HTTP_REFERER" => "https://my.dawarich.app:9000/admin/dash?q=1#hash")
      expect(result).to eq "https://my.dawarich.app:9000"
    end

    it "rejects 'null' Origin (sandboxed iframes/data URIs send this)" do
      result = call_with("HTTP_ORIGIN" => "null")
      expect(result).to be_nil
    end

    it "caps origin length at 200 characters" do
      huge = "https://" + ("a" * 250) + ".example.com"
      result = call_with("HTTP_ORIGIN" => huge)
      expect(result).to be_nil
    end
  end
end
