redis_config = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
}

# Heroku Redis uses self-signed certs with rediss:// URLs
if redis_config[:url]&.start_with?("rediss://")
  redis_config[:ssl_params] = { verify_mode: OpenSSL::SSL::VERIFY_NONE }
end

Sidekiq.configure_server do |config|
  config.redis = redis_config
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end
