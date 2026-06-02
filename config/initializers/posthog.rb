# frozen_string_literal: true

# PostHog error monitoring + product analytics, mirroring the Dawarich setup.
# No-op unless POSTHOG_API_KEY is set, so self-hosted instances without a key
# are completely unaffected.
return if ENV["POSTHOG_API_KEY"].blank?

PostHog::Rails.configure do |config|
  # Automatically capture unhandled exceptions (and the ones Rails rescues).
  config.auto_capture_exceptions    = true
  config.report_rescued_exceptions  = true
  # Capture exceptions raised inside ActiveJob (Solid Queue) jobs too.
  config.auto_instrument_active_job = true
  # Tag exceptions with the authenticated user's id only (no email/name).
  config.capture_user_context       = true
  config.current_user_method        = :current_user
end

PostHog.init do |config|
  config.api_key          = ENV.fetch("POSTHOG_API_KEY", nil)
  config.host             = ENV.fetch("POSTHOG_HOST", "https://eu.i.posthog.com")
  config.personal_api_key = ENV.fetch("POSTHOG_PERSONAL_API_KEY", nil)
  config.max_queue_size   = 10_000

  # Never emit events from the test suite.
  config.test_mode = true if Rails.env.test?
end
