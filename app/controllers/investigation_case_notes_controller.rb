class InvestigationCaseNotesController < ApplicationController
  def create
    investigation_case = current_user.investigation_cases.find(params[:case_id])
    case_note = investigation_case.case_notes.build(case_note_params.merge(user: current_user))

    if case_note.save
      redirect_to case_path(investigation_case, return_to: normalized_return_to), notice: "Note added."
    else
      redirect_back fallback_location: case_path(investigation_case, return_to: normalized_return_to), alert: case_note.errors.full_messages.to_sentence
    end
  end

  private

  def normalized_return_to
    value = params[:return_to].to_s
    return nil if value.blank?
    return nil unless value.start_with?("/") && !value.start_with?("//")

    value
  end

  def case_note_params
    params.require(:investigation_case_note).permit(:body, :kind)
  end
end
