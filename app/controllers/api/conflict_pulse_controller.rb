module Api
  class ConflictPulseController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      data = ConflictPulseService.analyze
      expires_in 5.minutes, public: true
      render json: data.merge(count: data[:zones]&.size || 0)
    end
  end
end
