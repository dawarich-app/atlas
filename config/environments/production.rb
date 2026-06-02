require "active_support/core_ext/integer/time"
require_relative "../host_config"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager loading enabled. Devise 5.0+ works correctly with Zeitwerk
  # under Rails 8.1 (devise/#5731), and we now load action_mailer in
  # config/application.rb, so Devise::Mailer resolves cleanly.
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # Driven by CHIBICHANGE_FORCE_SSL env var via HostConfig (defaults to true).
  config.force_ssl = HostConfig.force_ssl?

  # Skip http-to-https redirect for the default health check endpoint.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT) if ENV["RAILS_LOG_TO_STDOUT"].present?

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info").to_sym

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  # Solid Queue runs on the primary DATABASE_URL connection (single-DB setup).
  config.active_job.queue_adapter = :solid_queue

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # Email delivery. URL options are always set (used to build links in emails);
  # SMTP delivery is wired only when SMTP_SERVER is provided, so self-hosters
  # without email configured are unaffected. See docs/self-host.md for the
  # SMTP_* variables.
  require_relative "../../lib/smtp_config"
  config.action_mailer.default_url_options = HostConfig.compute[:default_url_options]
  if SmtpConfig.configured?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings   = SmtpConfig.smtp_settings
  end
end
