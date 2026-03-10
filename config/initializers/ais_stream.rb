Rails.application.config.after_initialize do
  if defined?(Rails::Server) && ENV["AISSTREAM_API_KEY"].present?
    AisStreamService.start
  end
end
