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
        PollerRuntime.run_supervised
      end
    end

    # Both hooks stop only this process's loop. They used to call
    # PollerRuntimeState.request_pause!/request_stop!, which persist desired_state
    # for every process -- and dokku keeps the outgoing container alive for 60s
    # after the new one boots, so the old worker's shutdown wrote "stopped" over
    # the fresh worker's "running" and silently switched ingest back off on every
    # deploy. Operator intent belongs to the admin UI, not to container lifecycle.
    config.on(:quiet) do
      PollerRuntime.request_local_stop!
    end

    config.on(:shutdown) do
      PollerRuntime.request_local_stop!
      embedded_poller_thread&.join(5)
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end
