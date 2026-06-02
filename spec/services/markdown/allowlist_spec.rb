require "rails_helper"

RSpec.describe Markdown::Allowlist do
  describe "NODE_TYPES" do
    it "is a frozen array of strings" do
      expect(described_class::NODE_TYPES).to be_an(Array).and be_frozen
      expect(described_class::NODE_TYPES).to all(be_a(String))
    end

    it "contains the 9 permitted types" do
      expect(described_class::NODE_TYPES).to contain_exactly(
        "p", "strong", "em", "code", "a", "ul", "ol", "li", "text"
      )
    end
  end

  describe ".node?" do
    it "is true for allowlisted types" do
      expect(described_class.node?("p")).to be true
      expect(described_class.node?("a")).to be true
    end

    it "is false for non-allowlisted types" do
      expect(described_class.node?("h1")).to be false
      expect(described_class.node?("img")).to be false
      expect(described_class.node?("script")).to be false
    end
  end

  describe ".href?" do
    it "permits https" do
      expect(described_class.href?("https://example.com")).to be true
    end

    it "permits mailto" do
      expect(described_class.href?("mailto:foo@example.com")).to be true
    end

    it "rejects http" do
      expect(described_class.href?("http://example.com")).to be false
    end

    it "rejects javascript: pseudo-protocol" do
      expect(described_class.href?("javascript:alert(1)")).to be false
    end

    it "rejects data: URIs" do
      expect(described_class.href?("data:text/html,<script>alert(1)</script>")).to be false
    end

    it "rejects malformed input" do
      expect(described_class.href?(nil)).to be false
      expect(described_class.href?("")).to be false
      expect(described_class.href?("not a url")).to be false
    end

    it "is whitespace-trimmed and case-insensitive on the scheme" do
      expect(described_class.href?(" HTTPS://example.com ")).to be true
      expect(described_class.href?("JavaScript:alert(1)")).to be false
    end
  end
end
