redis_config = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
}

# Heroku Redis uses self-signed certs with rediss:// URLs.
# Use CA cert verification if available, otherwise accept Heroku's self-signed cert.
if redis_config[:url]&.start_with?("rediss://")
  if ENV["REDIS_CA_CERT"]
    redis_config[:ssl_params] = {
      verify_mode: OpenSSL::SSL::VERIFY_PEER,
      ca_file: ENV["REDIS_CA_CERT"],
    }
  else
    # Heroku Redis Essential does not provide CA certs — VERIFY_NONE is required.
    # The connection is still encrypted (TLS), just not CA-verified.
    redis_config[:ssl_params] = { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  end
end

Sidekiq.configure_server do |config|
  config.redis = redis_config
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end
