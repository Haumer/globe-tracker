module Api
  class GeographyBoundariesController < ApplicationController
    skip_before_action :authenticate_user!

    def show
      dataset = params[:dataset].to_s
      unless GeographyBoundaryService::DATASETS.key?(dataset)
        return render json: {
          error: "Unsupported boundary dataset",
          allowed_datasets: GeographyBoundaryService::DATASETS.keys,
        }, status: :unprocessable_content
      end

      payload = GeographyBoundaryService.fetch(dataset)
      unless payload
        return render json: {
          error: "Boundary dataset unavailable",
          dataset: dataset,
        }, status: :service_unavailable
      end

      expires_in 12.hours, public: true
      render json: payload
    rescue GeographyBoundaryService::UnsupportedDatasetError
      render json: {
        error: "Unsupported boundary dataset",
        allowed_datasets: GeographyBoundaryService::DATASETS.keys,
      }, status: :unprocessable_content
    end
  end
end
