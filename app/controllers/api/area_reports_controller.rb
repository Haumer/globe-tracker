module Api
  class AreaReportsController < ApplicationController
    skip_before_action :authenticate_user!

    def show
      report = AreaReport.generate(parse_bounds)
      render json: report
    end
  end
end
