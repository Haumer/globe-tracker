class InvestigationCaseNote < ApplicationRecord
  NOTE_KINDS = %w[note update brief].freeze

  belongs_to :investigation_case, touch: true, inverse_of: :case_notes
  belongs_to :user

  validates :body, presence: true, length: { maximum: 10_000 }
  validates :kind, inclusion: { in: NOTE_KINDS }
end
