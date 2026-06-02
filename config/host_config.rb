module HostConfig
  REQUIRED_PRODUCTION_VARS = %w[CHIBICHANGE_HOST RAILS_MASTER_KEY DATABASE_URL].freeze

  module_function

  def host
    ENV["CHIBICHANGE_HOST"]
  end

  def widget_host
    ENV["CHIBICHANGE_WIDGET_HOST"].presence || (host ? "https://#{host}" : "http://localhost:3000")
  end

  def force_ssl?
    return true if ENV["CHIBICHANGE_FORCE_SSL"].nil?
    ENV["CHIBICHANGE_FORCE_SSL"].to_s.downcase != "false"
  end

  def compute
    {
      default_url_options: {
        host: host || "localhost",
        protocol: force_ssl? ? "https" : "http"
      },
      widget_host: widget_host
    }
  end

  def validate_production!
    missing = REQUIRED_PRODUCTION_VARS.reject { |k| ENV[k].present? }
    return if missing.empty?

    raise <<~MSG
      Missing required environment variables in production: #{missing.join(", ")}

      See docs/self-host.md for the full list and example values.
    MSG
  end
end
