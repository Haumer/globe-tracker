Rails.application.config.after_initialize do
  # AIS ownership is explicit now: the dedicated poller runtime starts and stops
  # the stream, not the web process during boot.
end
