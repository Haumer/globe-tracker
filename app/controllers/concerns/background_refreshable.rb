module BackgroundRefreshable
  extend ActiveSupport::Concern

  private

  def enqueue_background_refresh(job_class, *job_args, key:, debounce:)
    queued = BackgroundRefreshScheduler.enqueue_once(job_class, *job_args, key: key, ttl: debounce)
    response.set_header("X-Background-Refresh", "queued") if queued
    queued
  end
end
