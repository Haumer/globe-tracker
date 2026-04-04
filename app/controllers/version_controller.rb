class VersionController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"

    render json: {
      revision: app_revision,
    }
  end
end
