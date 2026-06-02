require "rails_helper"

RSpec.describe TokenRendererHelper, type: :helper do
  describe "#render_tokens" do
    def r(tokens)
      helper.render_tokens(tokens).to_s
    end

    it "renders a paragraph with text" do
      tokens = [{ "t" => "p", "c" => [{ "t" => "text", "v" => "hello" }] }]
      expect(r(tokens)).to eq "<p>hello</p>"
    end

    it "renders strong/em" do
      tokens = [{ "t" => "p", "c" => [
        { "t" => "strong", "c" => [{ "t" => "text", "v" => "bold" }] },
        { "t" => "text", "v" => " " },
        { "t" => "em", "c" => [{ "t" => "text", "v" => "ital" }] }
      ]}]
      expect(r(tokens)).to eq "<p><strong>bold</strong> <em>ital</em></p>"
    end

    it "renders code" do
      tokens = [{ "t" => "code", "v" => "Foo&Bar" }]
      expect(r(tokens)).to eq "<code>Foo&amp;Bar</code>"
    end

    it "renders a link with rel/target attrs" do
      tokens = [{ "t" => "p", "c" => [
        { "t" => "a", "href" => "https://x.com", "c" => [{ "t" => "text", "v" => "x" }] }
      ]}]
      expect(r(tokens)).to eq %(<p><a href="https://x.com" rel="noopener noreferrer" target="_blank">x</a></p>)
    end

    it "renders ul/ol/li" do
      tokens = [{ "t" => "ul", "c" => [
        { "t" => "li", "c" => [{ "t" => "text", "v" => "a" }] },
        { "t" => "li", "c" => [{ "t" => "text", "v" => "b" }] }
      ]}]
      expect(r(tokens)).to eq "<ul><li>a</li><li>b</li></ul>"
    end

    it "html-escapes text" do
      tokens = [{ "t" => "text", "v" => "<script>x</script>" }]
      expect(r(tokens)).to eq "&lt;script&gt;x&lt;/script&gt;"
    end

    it "drops unknown node types silently" do
      tokens = [{ "t" => "h1", "c" => [{ "t" => "text", "v" => "danger" }] }]
      expect(r(tokens)).to eq ""
    end

    it "drops anchors with disallowed schemes (defense in depth)" do
      tokens = [{ "t" => "p", "c" => [
        { "t" => "a", "href" => "javascript:alert(1)", "c" => [{ "t" => "text", "v" => "click" }] }
      ]}]
      expect(r(tokens)).to eq "<p>click</p>"
    end
  end
end
