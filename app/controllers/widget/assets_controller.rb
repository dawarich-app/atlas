class Widget::AssetsController < ApplicationController
  # Cross-origin <script> embedding is the entire point of this endpoint.
  skip_forgery_protection

  BUNDLE_PATH = Rails.root.join("app/assets/builds/widget.v1.js").to_s

  def loader
    unless File.exist?(BUNDLE_PATH)
      head :not_found
      return
    end

    # Conditional GET — when the bundle hasn't changed, return 304 with no
    # body. ETag combines file size + mtime so any edit invalidates caches
    # without us needing to bump a version string manually.
    last_modified = File.mtime(BUNDLE_PATH)
    bundle_etag   = "widget-#{File.size(BUNDLE_PATH)}-#{last_modified.to_i}"
    return unless stale?(etag: bundle_etag, last_modified: last_modified, public: true)

    # Cache policy:
    #   max-age=300                   → 5 minutes of fresh serving
    #   stale-while-revalidate=60     → ≤1 minute of stale-while-fetching after
    #                                   that, then a strict 304-or-fresh check
    # Worst-case staleness after a deploy: ~6 minutes. The 24h SWR we shipped
    # initially made bugfixes invisible for a day in the wild.
    response.headers["Cache-Control"]          = "public, max-age=300, stale-while-revalidate=60"
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_file BUNDLE_PATH, type: "application/javascript", disposition: "inline"
  end
end
