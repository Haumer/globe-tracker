Rails.application.config.after_initialize do
  # AIS is never started from web boot.
  # The dedicated poller process owns the AIS stream lifecycle.
end
