class ApplicationController < ActionController::Base
  include BackgroundRefreshable
  include ApiHelpers

  before_action :authenticate_user!
  after_action :prevent_html_caching

  helper_method :app_revision

  private

  def app_revision
    AppRevision.current
  end

  def prevent_html_caching
    return unless request.format&.html?

    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
  end
end
