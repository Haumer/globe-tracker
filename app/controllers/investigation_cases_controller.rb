class InvestigationCasesController < ApplicationController
  before_action :set_investigation_case, only: [:show]

  def index
    @investigation_cases = current_user.investigation_cases
      .includes(:case_objects, case_notes: :user)
      .recent
    @meta_title = "Cases | GlobeTracker"
    @meta_description = "Track pinned objects, analyst notes, and durable operational context across your investigation cases."
  end

  def show
    @case_objects = @investigation_case.case_objects
    @case_notes = @investigation_case.case_notes.includes(:user)
    @case_note = @investigation_case.case_notes.build
    @meta_title = "#{@investigation_case.title} | GlobeTracker"
    @meta_description = @investigation_case.summary.presence || "#{@case_objects.size} pinned objects and #{@case_notes.size} notes in this investigation case."
  end

  def create
    @investigation_case = current_user.investigation_cases.build(investigation_case_params)
    attach_source_object(@investigation_case, source_object_params)

    if @investigation_case.save
      redirect_to case_path(@investigation_case), notice: "Case created."
    else
      redirect_back fallback_location: cases_path, alert: @investigation_case.errors.full_messages.to_sentence
    end
  end

  private

  def set_investigation_case
    @investigation_case = current_user.investigation_cases.find(params[:id])
  end

  def investigation_case_params
    params.fetch(:investigation_case, {}).permit(:title, :summary, :status, :severity)
  end

  def attach_source_object(investigation_case, payload)
    return if payload.blank?

    investigation_case.case_objects.build(InvestigationCaseObject.attributes_from_payload(payload))
  end

  def source_object_params
    params.permit(
      source_object: [
        :object_kind,
        :object_identifier,
        :title,
        :summary,
        :object_type,
        :latitude,
        :longitude,
        { source_context: {} }
      ]
    )[:source_object]
  end
end
