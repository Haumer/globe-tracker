class InvestigationCase < ApplicationRecord
  STATUSES = %w[open monitoring escalated closed].freeze
  SEVERITIES = %w[low medium high critical].freeze

  belongs_to :user
  belongs_to :assignee, class_name: "User", optional: true

  has_many :case_objects,
    -> { order(created_at: :asc) },
    class_name: "InvestigationCaseObject",
    dependent: :destroy,
    inverse_of: :investigation_case
  has_many :case_notes,
    -> { order(created_at: :desc) },
    class_name: "InvestigationCaseNote",
    dependent: :destroy,
    inverse_of: :investigation_case

  validates :title, presence: true, length: { maximum: 140 }
  validates :summary, length: { maximum: 5000 }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }
  validates :severity, inclusion: { in: SEVERITIES }

  scope :recent, -> { order(updated_at: :desc, created_at: :desc) }

  def case_code
    return "DRAFT" unless persisted?

    "CASE-#{id.to_s.rjust(5, "0")}"
  end

  def assignee_email
    assignee&.email || "Unassigned"
  end
end
