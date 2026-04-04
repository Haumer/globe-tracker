module AppRevision
  module_function

  def current
    return resolved_revision unless cacheable_revision?

    @current ||= resolved_revision
  end

  def cacheable_revision?
    Rails.env.production?
  end

  def resolved_revision
    ENV["APP_REVISION"].presence ||
      ENV["SOURCE_VERSION"].presence ||
      ENV["HEROKU_SLUG_COMMIT"].presence ||
      ENV["HEROKU_RELEASE_VERSION"].presence ||
      Rails.application.importmap.digest(resolver: ActionController::Base.helpers)
  end
end
