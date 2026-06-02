module Markdown
  module Allowlist
    NODE_TYPES = %w[p strong em code a ul ol li text].freeze
    HREF_SCHEMES = %w[https mailto].freeze

    def self.node?(type)
      NODE_TYPES.include?(type)
    end

    def self.href?(href)
      return false unless href.is_a?(String)

      stripped = href.strip
      return false if stripped.empty?

      uri = URI.parse(stripped)
      return false if uri.scheme.nil?

      HREF_SCHEMES.include?(uri.scheme.downcase)
    rescue URI::InvalidURIError
      false
    end
  end
end
