require "rails_helper"

RSpec.describe "Markdown XSS corpus", type: :model do
  CORPUS_GLOB = Rails.root.join("spec/fixtures/markdown_xss_corpus/*.md")

  Dir.glob(CORPUS_GLOB).sort.each do |path|
    describe File.basename(path) do
      let(:tokens) { Markdown::Tokenizer.call(File.read(path)) }
      let(:flat)   { flatten(tokens) }

      it "produces no nodes outside the allowlist" do
        flat.each do |node|
          next if node.is_a?(String)
          expect(Markdown::Allowlist.node?(node["t"])).to be(true),
            "node type #{node['t'].inspect} not in allowlist (in #{File.basename(path)})"
        end
      end

      it "produces no link nodes whose href is not in the allowlist" do
        anchors = flat.select { |n| n.is_a?(Hash) && n["t"] == "a" }
        anchors.each do |a|
          expect(Markdown::Allowlist.href?(a["href"])).to be(true),
            "anchor href #{a['href'].inspect} bypassed allowlist (in #{File.basename(path)})"
        end
      end

      it "contains no string literals matching script/onerror/javascript:/data:" do
        text_blob = flat.select { |n| n.is_a?(Hash) && n["t"] == "text" }
                        .map { |n| n["v"] }.join(" ")
        expect(text_blob).not_to match(/<script|onerror|javascript:|data:text/i)
      end
    end
  end

  # Walk the token tree, returning an array of every node Hash and child Hash.
  def flatten(nodes)
    nodes.flat_map do |n|
      next [n] unless n.is_a?(Hash)
      [n, *flatten(n["c"] || [])]
    end
  end
end
