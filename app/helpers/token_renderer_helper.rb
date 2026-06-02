module TokenRendererHelper
  ALLOWED_TAGS = %w[p strong em code a ul ol li].freeze

  def render_tokens(tokens)
    safe_join(Array(tokens).map { |n| render_node(n) })
  end

  def render_tokens_to_html(tokens)
    render_tokens(tokens).to_s
  end

  private

  def render_node(node)
    return "".html_safe unless node.is_a?(Hash)

    case node["t"]
    when "text" then h(node["v"].to_s)
    when "code" then content_tag(:code, h(node["v"].to_s))
    when "p", "strong", "em", "ul", "ol", "li"
      content_tag(node["t"].to_sym, render_tokens(node["c"]))
    when "a"
      if Markdown::Allowlist.href?(node["href"])
        content_tag(:a, render_tokens(node["c"]), href: node["href"], rel: "noopener noreferrer", target: "_blank")
      else
        render_tokens(node["c"])
      end
    else
      "".html_safe
    end
  end
end
