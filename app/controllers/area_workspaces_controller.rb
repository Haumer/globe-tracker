class AreaWorkspacesController < ApplicationController
  before_action :set_area_workspace, only: :show

  def index
    @area_workspaces = current_user.area_workspaces.recent
    @meta_title = "Areas | GlobeTracker"
    @meta_description = "Saved regional workspaces for monitoring countries, theaters, and custom globe selections."
  end

  def show
    @summary = AreaSummaryService.new(@area_workspace).call
    @meta_title = "#{@area_workspace.name} | GlobeTracker"
    @meta_description = @area_workspace.scope_detail
  end

  def create
    @area_workspace = current_user.area_workspaces.build(area_workspace_params)

    if @area_workspace.save
      respond_to do |format|
        format.html { redirect_to area_path(@area_workspace), notice: "Area saved." }
        format.json do
          render json: {
            id: @area_workspace.id,
            name: @area_workspace.name,
            path: area_path(@area_workspace),
          }, status: :created
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to root_path, alert: @area_workspace.errors.full_messages.to_sentence.presence || "Failed to save area workspace" }
        format.json { render json: { errors: @area_workspace.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_area_workspace
    @area_workspace = current_user.area_workspaces.find(params[:id])
  end

  def area_workspace_params
    permitted = params.require(:area_workspace).permit(
      :name,
      :scope_type,
      :profile,
      bounds: {},
      scope_metadata: {},
      default_layers: []
    )

    permitted.to_h
  end
end
