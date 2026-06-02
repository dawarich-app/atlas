module OriginNormalizer
  ALLOWED_SCHEMES = %w[http https].freeze
  DEFAULT_PORTS   = { "http" => 80, "https" => 443 }.freeze
  MAX_LENGTH      = 200

  module_function

  # Returns a normalized origin string "scheme://host[:port]" or nil.
  def call(request)
    raw = request.get_header("HTTP_ORIGIN").presence || request.get_header("HTTP_REFERER").presence
    return nil if raw.nil? || raw == "null"
    return nil if raw.length > MAX_LENGTH

    uri = URI.parse(raw.strip)
    return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    return nil unless ALLOWED_SCHEMES.include?(uri.scheme&.downcase)
    return nil if uri.host.nil? || uri.host.empty?

    scheme = uri.scheme.downcase
    host   = uri.host.downcase
    port   = uri.port

    if port.nil? || port == DEFAULT_PORTS[scheme]
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  rescue URI::InvalidURIError
    nil
  end
end
