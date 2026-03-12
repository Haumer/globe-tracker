module Api
  class WorkspacesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_workspace, only: [:update, :destroy]

    def index
      render json: current_user.workspaces.ordered.map { |w| workspace_json(w) }
    end

    def create
      workspace = current_user.workspaces.build(workspace_params)
      if workspace.save
        render json: workspace_json(workspace), status: :created
      else
        render json: { errors: workspace.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      if @workspace.update(workspace_params)
        render json: workspace_json(@workspace)
      else
        render json: { errors: @workspace.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @workspace.destroy!
      head :no_content
    end

    private

    def set_workspace
      @workspace = current_user.workspaces.find(params[:id])
    end

    def workspace_params
      params.permit(
        :name, :is_default, :shared,
        :camera_lat, :camera_lng, :camera_height, :camera_heading, :camera_pitch,
        layers: {},
        filters: {}
      )
    end

    def workspace_json(w)
      {
        id: w.id,
        name: w.name,
        is_default: w.is_default,
        shared: w.shared,
        slug: w.slug,
        camera_lat: w.camera_lat,
        camera_lng: w.camera_lng,
        camera_height: w.camera_height,
        camera_heading: w.camera_heading,
        camera_pitch: w.camera_pitch,
        layers: w.layers,
        filters: w.filters,
        updated_at: w.updated_at.iso8601,
      }
    end
  end
end
