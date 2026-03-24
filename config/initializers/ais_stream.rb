Rails.application.config.after_initialize do
  auto_start_background_services = if ENV.key?("AUTO_START_BACKGROUND_SERVICES")
    ENV["AUTO_START_BACKGROUND_SERVICES"] == "1"
  else
    Rails.env.production?
  end

  if auto_start_background_services && defined?(Rails::Server) && ENV["AISSTREAM_API_KEY"].present?
    AisStreamService.start
  end
end
