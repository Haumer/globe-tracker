class Rack::Attack
  # Use Rails.cache as the backing store
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # ── Throttles ──────────────────────────────────────────────────

  # General API: 120 requests per minute per IP
  throttle("api/ip", limit: 120, period: 60) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  # Stricter limit on heavy endpoints (exports, playback)
  throttle("api/heavy/ip", limit: 10, period: 60) do |req|
    req.ip if req.path.start_with?("/api/exports/", "/api/playback")
  end

  # Auth endpoints: 5 attempts per 20 seconds per IP
  throttle("auth/ip", limit: 5, period: 20) do |req|
    req.ip if req.path.start_with?("/users/sign_in") && req.post?
  end

  # Sign up: 3 attempts per minute per IP
  throttle("signup/ip", limit: 3, period: 60) do |req|
    req.ip if req.path.start_with?("/users") && req.post? && !req.path.include?("sign_in")
  end

  # ── Blocklist ──────────────────────────────────────────────────

  # Block requests with suspicious patterns
  blocklist("bad-agents") do |req|
    req.user_agent.blank? && req.path.start_with?("/api/") && !req.path.include?("health")
  end

  # ── Response ───────────────────────────────────────────────────

  self.throttled_responder = lambda do |req|
    now = req.env["rack.attack.match_data"][:epoch_time]
    retry_after = req.env["rack.attack.match_data"][:period] - (now % req.env["rack.attack.match_data"][:period])

    [
      429,
      {
        "Content-Type" => "application/json",
        "Retry-After" => retry_after.to_s,
      },
      [{ error: "Rate limit exceeded. Retry after #{retry_after} seconds." }.to_json],
    ]
  end
end
