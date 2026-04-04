require "active_support/core_ext/integer/time"

require Rails.root.join("lib/redis_ssl_config")

Rails.application.configure do
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "globe-tracker-eece3877b792.herokuapp.com"), protocol: "https" }
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Ensures that a master key has been made available in ENV["RAILS_MASTER_KEY"], config/master.key, or an environment
  # key such as config/credentials/production.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Heroku serves from the app process, so enable the public file server there and
  # rely on precompiled assets instead of runtime asset compilation.
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present? || ENV["DYNO"].present?

  # Compress CSS using a preprocessor.
  # config.assets.css_compressor = :sass

  # Do not fall back to runtime asset compilation in production.
  config.assets.compile = false

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = ENV["ACTIVE_STORAGE_SERVICE"]&.to_sym || :local

  # Mount Action Cable on the same Puma process
  config.action_cable.mount_path = "/cable"
  config.action_cable.allowed_request_origins = [
    "https://globe-tracker-eece3877b792.herokuapp.com",
    /https:\/\/.*\.herokuapp\.com/,
  ]

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Can be used together with config.force_ssl for Strict-Transport-Security and secure cookies.
  # config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Log to STDOUT by default
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  # "info" includes generic and useful information about system operation, but avoids logging too much
  # information to avoid inadvertent exposure of personally identifiable information (PII). If you
  # want to log everything, set the level to "debug".
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  cache_backend = ENV.fetch("CACHE_BACKEND", "memory")
  if cache_backend == "redis"
    redis_cache_opts = {
      url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
      expires_in: 10.minutes,
      connect_timeout: 2,
      read_timeout: 1,
      write_timeout: 1,
      reconnect_attempts: 1,
      error_handler: ->(method:, returning:, exception:) {
        Rails.logger.warn("Redis cache error: #{exception.class} - #{exception.message}")
      },
    }
    if (redis_ssl_params = RedisSslConfig.params_for(ENV["REDIS_URL"]))
      redis_cache_opts[:ssl_params] = redis_ssl_params
    end
    config.cache_store = :redis_cache_store, redis_cache_opts
  else
    cache_size_mb = ENV.fetch("MEMORY_CACHE_SIZE_MB", "64").to_i
    config.cache_store = :memory_store, { size: cache_size_mb.megabytes }
  end

  config.active_job.queue_adapter = :sidekiq

  config.action_mailer.perform_caching = false

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Enable DNS rebinding protection and other `Host` header attacks.
  config.hosts = [
    ENV.fetch("APP_HOST", "globe-tracker-eece3877b792.herokuapp.com"),
    /.*\.herokuapp\.com/,
  ]
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
