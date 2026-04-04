class InvestigationCasesController < ApplicationController
  before_action :set_investigation_case, only: [:show, :update]
  before_action :set_assignable_users, only: [:new, :show]

  def index
    @investigation_cases = current_user.investigation_cases
      .includes(:assignee, :case_objects, case_notes: :user)
      .recent
    @meta_title = "Cases | GlobeTracker"
    @meta_description = "Track pinned objects, analyst notes, and durable operational context across your investigation cases."
  end

  def new
    @source_object = source_object_payload
    @return_to_globe = normalized_return_to
    @available_cases = current_user.investigation_cases.includes(:assignee).recent.limit(10)
    @investigation_case = current_user.investigation_cases.build(
      title: default_case_title(@source_object),
      summary: @source_object[:summary],
      status: "open",
      severity: default_case_severity(@source_object),
      assignee: current_user
    )
    @meta_title = "New Case | GlobeTracker"
    @meta_description = @source_object[:title].present? ? "Create a case for #{@source_object[:title]} and preserve the current operating picture." : "Create a new investigation case."
  end

  def show
    @return_to_globe = normalized_return_to
    @case_objects = @investigation_case.case_objects
    @case_notes = @investigation_case.case_notes.includes(:user)
    @case_note = @investigation_case.case_notes.build
    @available_cases = current_user.investigation_cases.where.not(id: @investigation_case.id).includes(:assignee).recent.limit(10)
    @meta_title = "#{@investigation_case.title} | GlobeTracker"
    @meta_description = @investigation_case.summary.presence || "#{@case_objects.size} pinned objects and #{@case_notes.size} notes in this investigation case."
  end

  def create
    @investigation_case = current_user.investigation_cases.build(investigation_case_params)
    @investigation_case.assignee ||= current_user
    attach_source_object(@investigation_case, source_object_params)

    if @investigation_case.save
      redirect_to case_path(@investigation_case, return_to: normalized_return_to), notice: "Case created."
    else
      @source_object = source_object_payload
      @return_to_globe = normalized_return_to
      @available_cases = current_user.investigation_cases.includes(:assignee).recent.limit(10)
      set_assignable_users
      @meta_title = "New Case | GlobeTracker"
      @meta_description = "Create a new investigation case."
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @investigation_case.update(investigation_case_update_params)
      redirect_to case_path(@investigation_case, return_to: normalized_return_to), notice: "Case updated."
    else
      @return_to_globe = normalized_return_to
      @case_objects = @investigation_case.case_objects
      @case_notes = @investigation_case.case_notes.includes(:user)
      @case_note = @investigation_case.case_notes.build
      @available_cases = current_user.investigation_cases.where.not(id: @investigation_case.id).includes(:assignee).recent.limit(10)
      @meta_title = "#{@investigation_case.title} | GlobeTracker"
      @meta_description = @investigation_case.summary.presence || "#{@case_objects.size} pinned objects and #{@case_notes.size} notes in this investigation case."
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_investigation_case
    @investigation_case = current_user.investigation_cases.find(params[:id])
  end

  def investigation_case_params
    permitted = params.fetch(:investigation_case, {}).permit(:title, :summary, :status, :severity, :assignee_id)
    normalize_case_params(permitted)
  end

  def investigation_case_update_params
    permitted = params.require(:investigation_case).permit(:title, :summary, :status, :severity, :assignee_id)
    normalize_case_params(permitted)
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

  def source_object_payload
    payload = source_object_params
    return {} if payload.blank?

    InvestigationCaseObject.attributes_from_payload(payload)
  end

  def normalize_case_params(permitted)
    attrs = permitted.to_h
    attrs["assignee_id"] = nil if attrs["assignee_id"].blank?
    attrs
  end

  def set_assignable_users
    @assignable_users = User.order(:email)
  end

  def normalized_return_to
    value = params[:return_to].to_s
    return nil if value.blank?
    return nil unless value.start_with?("/") && !value.start_with?("//")

    value
  end

  def default_case_title(source_object)
    return "New case" if source_object[:title].blank?

    "Investigate #{source_object[:title]}"
  end

  def default_case_severity(source_object)
    source_context = source_object[:source_context] || {}
    severity = source_context["severity"] || source_context[:severity]
    return severity if InvestigationCase::SEVERITIES.include?(severity)

    "medium"
  end
end
