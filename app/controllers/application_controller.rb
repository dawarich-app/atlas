class ApplicationController < ActionController::Base
  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Note: `allow_browser versions: :modern` is intentionally NOT enforced here.
  # The widget endpoints (`/w/v1/*`) are loaded as cross-origin <script> tags from
  # arbitrary host pages and MUST work in any browser the host serves. Public
  # changelog pages (`/c/*`) and Devise auth pages stay permissive too. The
  # modern-browser gate is applied only to the authors dashboard
  # (Authors::BaseController), where Hotwire interactivity actually requires it.
end
