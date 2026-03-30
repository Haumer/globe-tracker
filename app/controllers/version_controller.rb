class VersionController < ActionController::Base
  def show
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"

    render json: {
      revision: Rails.application.importmap.digest(resolver: helpers),
    }
  end
end
