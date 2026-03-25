Rails.application.config.after_initialize do
  # AIS is never started from web boot.
  # Under the current Heroku Scheduler + Sidekiq model, persistent AIS streaming
  # is disabled because Scheduler cannot host long-lived websocket workers.
end
