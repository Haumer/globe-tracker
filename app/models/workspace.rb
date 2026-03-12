class Workspace < ApplicationRecord
  belongs_to :user

  validates :name, presence: true, length: { maximum: 100 }
  validates :slug, uniqueness: true, allow_nil: true

  before_save :generate_slug, if: -> { shared? && slug.blank? }
  before_save :clear_slug, if: -> { !shared? && slug.present? }
  after_save :ensure_single_default, if: -> { is_default? && saved_change_to_is_default? }

  scope :ordered, -> { order(is_default: :desc, updated_at: :desc) }

  private

  def generate_slug
    base = name.parameterize.first(40)
    self.slug = base
    counter = 1
    while Workspace.where(slug: slug).where.not(id: id).exists?
      self.slug = "#{base}-#{counter}"
      counter += 1
    end
  end

  def clear_slug
    self.slug = nil
  end

  def ensure_single_default
    user.workspaces.where(is_default: true).where.not(id: id).update_all(is_default: false)
  end
end
