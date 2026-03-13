module Api
  class AreaReportsController < ApplicationController
    skip_before_action :authenticate_user!

    def show
      bounds = {
        lamin: params[:lamin].to_f,
        lamax: params[:lamax].to_f,
        lomin: params[:lomin].to_f,
        lomax: params[:lomax].to_f,
      }
      report = AreaReport.generate(bounds)
      render json: report
    end
  end
end
