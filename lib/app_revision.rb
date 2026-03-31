module AppRevision
  module_function

  def current
    @current ||= begin
      ENV["APP_REVISION"].presence ||
        ENV["SOURCE_VERSION"].presence ||
        ENV["HEROKU_SLUG_COMMIT"].presence ||
        ENV["HEROKU_RELEASE_VERSION"].presence ||
        Rails.application.importmap.digest(resolver: ActionController::Base.helpers)
    end
  end
end
