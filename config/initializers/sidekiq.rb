require Rails.root.join("lib/redis_ssl_config")

redis_config = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
}

if (redis_ssl_params = RedisSslConfig.params_for(redis_config[:url]))
  redis_config[:ssl_params] = redis_ssl_params
end

Sidekiq.configure_server do |config|
  config.redis = redis_config

  if ENV["EMBED_POLLER_IN_WORKER"] == "1"
    embedded_poller_thread = nil

    config.on(:startup) do
      embedded_poller_thread = Thread.new do
        Thread.current.name = "embedded-poller" if Thread.current.respond_to?(:name=)
        PollerRuntime.run
      end
    end

    config.on(:quiet) do
      PollerRuntimeState.request_pause!
    end

    config.on(:shutdown) do
      PollerRuntimeState.request_stop!
      embedded_poller_thread&.join(5)
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end
