class Rack::Attack
  # In production, Rails.cache → Solid Cache (shared across workers).
  # In test, Rails.cache → MemoryStore (set in config/environments/test.rb).
  # In development, Rails.cache → MemoryStore (Rails default).
  Rack::Attack.cache.store = Rails.cache

  throttle("widget/origin", limit: 60, period: 60.seconds) do |req|
    next unless req.path.start_with?("/w/v1/") && req.path.end_with?(".json")

    OriginNormalizer.call(ActionDispatch::Request.new(req.env)) || req.ip
  end

  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"] || {}
    retry_after = match_data[:period] || 60
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s,
        "Access-Control-Allow-Origin" => "*", "Cache-Control" => "no-store" },
      ["{}"]
    ]
  end
end
