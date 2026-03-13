module Api
  class WatchesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_watch, only: [:update, :destroy]

    def index
      render json: current_user.watches.order(created_at: :desc).map { |w| watch_json(w) }
    end

    def create
      watch = current_user.watches.build(watch_params)
      if watch.save
        render json: watch_json(watch), status: :created
      else
        render json: { errors: watch.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      if @watch.update(watch_params)
        render json: watch_json(@watch)
      else
        render json: { errors: @watch.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @watch.destroy!
      head :no_content
    end

    private

    def set_watch
      @watch = current_user.watches.find(params[:id])
    end

    def watch_params
      params.permit(:name, :watch_type, :notify_via, :active, :cooldown_minutes, conditions: {})
    end

    def watch_json(w)
      {
        id: w.id,
        name: w.name,
        watch_type: w.watch_type,
        conditions: w.conditions,
        notify_via: w.notify_via,
        active: w.active,
        cooldown_minutes: w.cooldown_minutes,
        last_triggered_at: w.last_triggered_at&.iso8601,
        created_at: w.created_at.iso8601,
      }
    end
  end
end
