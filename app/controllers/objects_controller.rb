class ObjectsController < ApplicationController
  skip_before_action :authenticate_user!

  rescue_from NodeContextService::UnsupportedNodeError do |error|
    render_object_error(error.message, :unprocessable_entity)
  end

  rescue_from NodeContextService::NodeNotFoundError do |error|
    render_object_error(error.message, :not_found)
  end

  def show
    @object_request = {
      kind: params[:kind].to_s,
      id: params[:id].to_s,
    }
    @object_context = NodeContextService.resolve(**@object_request.symbolize_keys)
    @object_node = @object_context.fetch(:node)
    @available_cases = current_user&.investigation_cases&.recent&.limit(8) || []
    @meta_title = "#{@object_node[:name]} | GlobeTracker"
    @meta_description = @object_node[:summary].presence || "Inspect durable relationships, evidence, and memberships for this operational object."
  end

  private

  def render_object_error(message, status)
    @object_request = {
      kind: params[:kind].to_s,
      id: params[:id].to_s,
    }
    @object_error = message
    render :show, status: status
  end
end
