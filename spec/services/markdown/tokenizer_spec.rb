require "rails_helper"

RSpec.describe Markdown::Tokenizer do
  def tok(str)
    described_class.call(str)
  end

  describe "happy path" do
    it "renders plain text inside a paragraph" do
      expect(tok("hello world")).to eq([
        { "t" => "p", "c" => [{ "t" => "text", "v" => "hello world" }] }
      ])
    end

    it "renders bold and italic" do
      expect(tok("**bold** and *italic*")).to eq([
        { "t" => "p", "c" => [
          { "t" => "strong", "c" => [{ "t" => "text", "v" => "bold" }] },
          { "t" => "text", "v" => " and " },
          { "t" => "em", "c" => [{ "t" => "text", "v" => "italic" }] }
        ] }
      ])
    end

    it "renders inline code" do
      expect(tok("use `Markdown::Allowlist`")).to eq([
        { "t" => "p", "c" => [
          { "t" => "text", "v" => "use " },
          { "t" => "code", "v" => "Markdown::Allowlist" }
        ] }
      ])
    end

    it "renders an https link" do
      expect(tok("[docs](https://example.com)")).to eq([
        { "t" => "p", "c" => [
          { "t" => "a", "href" => "https://example.com",
            "c" => [{ "t" => "text", "v" => "docs" }] }
        ] }
      ])
    end

    it "renders a mailto link" do
      expect(tok("[mail](mailto:foo@example.com)")).to eq([
        { "t" => "p", "c" => [
          { "t" => "a", "href" => "mailto:foo@example.com",
            "c" => [{ "t" => "text", "v" => "mail" }] }
        ] }
      ])
    end

    it "renders an unordered list" do
      result = tok("- one\n- two")
      expect(result.size).to eq 1
      expect(result.first["t"]).to eq "ul"
      expect(result.first["c"].size).to eq 2
      expect(result.first["c"].map { _1["t"] }).to eq %w[li li]
    end

    it "renders an ordered list" do
      result = tok("1. one\n2. two")
      expect(result.first["t"]).to eq "ol"
    end
  end

  describe "drops non-allowlisted nodes" do
    it "drops headings, keeps the text" do
      expect(tok("# hello")).to eq([{ "t" => "text", "v" => "hello" }])
    end

    it "drops images entirely" do
      expect(tok("an ![alt](https://example.com/x.png) image")).to eq([
        { "t" => "p", "c" => [
          { "t" => "text", "v" => "an " },
          { "t" => "text", "v" => " image" }
        ] }
      ])
    end

    it "drops blockquotes, promotes children" do
      expect(tok("> quoted")).to eq([
        { "t" => "p", "c" => [{ "t" => "text", "v" => "quoted" }] }
      ])
    end

    it "drops code blocks (fenced), keeps no content" do
      result = tok("```ruby\nputs :hi\n```")
      # code blocks are not in the allowlist; the safest behavior is to drop
      expect(result).to eq([])
    end
  end

  describe "link scheme validation" do
    it "drops javascript: links, keeps text" do
      expect(tok("[click](javascript:alert(1))")).to eq([
        { "t" => "p", "c" => [{ "t" => "text", "v" => "click" }] }
      ])
    end

    it "drops http: links, keeps text" do
      expect(tok("[click](http://example.com)")).to eq([
        { "t" => "p", "c" => [{ "t" => "text", "v" => "click" }] }
      ])
    end

    it "drops data: links, keeps text" do
      expect(tok("[click](data:text/html,<script>)")).to eq([
        { "t" => "p", "c" => [{ "t" => "text", "v" => "click" }] }
      ])
    end
  end

  describe "edge cases" do
    it "returns [] for nil" do
      expect(tok(nil)).to eq []
    end

    it "returns [] for empty string" do
      expect(tok("")).to eq []
    end

    it "returns [] for whitespace-only" do
      expect(tok("   \n\n  ")).to eq []
    end
  end
end
