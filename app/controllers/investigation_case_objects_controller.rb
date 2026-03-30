class InvestigationCaseObjectsController < ApplicationController
  def create
    investigation_case = current_user.investigation_cases.find(case_object_params[:investigation_case_id])
    object_attributes = InvestigationCaseObject.attributes_from_payload(case_object_params.except(:investigation_case_id))
    case_object = investigation_case.case_objects.find_or_initialize_by(
      object_kind: object_attributes[:object_kind],
      object_identifier: object_attributes[:object_identifier]
    )
    existed = case_object.persisted?
    case_object.assign_attributes(object_attributes)

    if case_object.save
      redirect_to case_path(investigation_case), notice: existed ? "Object refreshed in case." : "Object added to case."
    else
      redirect_back fallback_location: case_path(investigation_case), alert: case_object.errors.full_messages.to_sentence
    end
  end

  private

  def case_object_params
    params.require(:case_object).permit(
      :investigation_case_id,
      :object_kind,
      :object_identifier,
      :title,
      :summary,
      :object_type,
      :latitude,
      :longitude,
      source_context: {}
    )
  end
end
