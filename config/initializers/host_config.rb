require_relative "../host_config"

# Apply default_url_options when an explicit host is configured (mailers,
# ActionController::UrlFor, etc). Skip when CHIBICHANGE_HOST is unset so
# Rails' built-in test/dev defaults remain intact.
if HostConfig.host.present?
  Rails.application.config.action_controller.default_url_options = HostConfig.compute[:default_url_options]
  Rails.application.config.action_mailer.default_url_options    = HostConfig.compute[:default_url_options] if Rails.application.config.respond_to?(:action_mailer)
end

# Validate required vars in production at boot.
# Skip during asset precompile (SECRET_KEY_BASE_DUMMY=1), where Rails boots in
# production mode but is not actually serving requests — the standard Dockerfile
# convention for building container images without exposing real secrets.
if Rails.env.production? && !ENV["SECRET_KEY_BASE_DUMMY"]
  HostConfig.validate_production!
end
