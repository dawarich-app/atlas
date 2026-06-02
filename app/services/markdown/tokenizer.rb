require "commonmarker"

module Markdown
  module Tokenizer
    module_function

    # Block/inline wrapper nodes that are NOT in the allowlist but whose text
    # children should be promoted to the parent (the wrapper is stripped, the
    # content stays). Examples: a heading is dropped but its text remains.
    PROMOTE_CHILDREN_TYPES = %i[heading block_quote].freeze

    # Nodes that must be dropped together with all of their descendants.
    # Notably images: their inner :text child is the alt-text, which we do
    # NOT want leaking into the rendered output.
    DROP_ENTIRELY_TYPES = %i[
      image
      code_block
      html_block
      html_inline
      thematic_break
      softbreak
      linebreak
    ].freeze

    # Parses `markdown` and returns an Array of token nodes.
    # Drops nodes whose type is not in Markdown::Allowlist.
    def call(markdown)
      return [] if markdown.nil? || markdown.strip.empty?

      doc = Commonmarker.parse(markdown)
      walk_children(doc)
    end

    # Recursively walk a node's children and produce a flat array of token-tree nodes.
    # `transform` may return a Hash (single token), an Array (promoted children),
    # or nil (drop). We coerce all three into a flat list without using Kernel#Array,
    # which would turn a Hash into an array of [key, value] pairs.
    def walk_children(node)
      result = []
      node.each do |child|
        out = transform(child)
        case out
        when nil   then next
        when Array then result.concat(out)
        else            result << out
        end
      end
      result
    end

    # Returns a token (Hash), an Array of tokens (when promoting children),
    # or [] (when dropping the subtree entirely).
    def transform(node)
      case node.type
      when :paragraph then { "t" => "p",      "c" => walk_children(node) }
      when :strong   then { "t" => "strong", "c" => walk_children(node) }
      when :emph     then { "t" => "em",     "c" => walk_children(node) }
      when :list
        kind = node.list_type == :ordered ? "ol" : "ul"
        { "t" => kind, "c" => walk_children(node) }
      when :item then { "t" => "li", "c" => walk_children(node) }
      when :code then { "t" => "code", "v" => node.string_content.to_s }
      when :text then { "t" => "text", "v" => node.string_content.to_s }
      when :link
        href = node.url
        if Markdown::Allowlist.href?(href)
          { "t" => "a", "href" => href, "c" => walk_children(node) }
        else
          # Drop the link wrapper, keep the visible link text only.
          walk_children(node)
        end
      else
        if DROP_ENTIRELY_TYPES.include?(node.type)
          []
        elsif PROMOTE_CHILDREN_TYPES.include?(node.type)
          walk_children(node)
        else
          # Unknown node type: be conservative and drop the entire subtree.
          # Anything we want to render must be explicitly allowlisted above.
          []
        end
      end
    end
  end
end
