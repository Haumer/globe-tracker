class InvestigationCaseObject < ApplicationRecord
  belongs_to :investigation_case, touch: true, inverse_of: :case_objects

  validates :object_kind, :object_identifier, :title, presence: true
  validates :title, length: { maximum: 240 }
  validates :summary, length: { maximum: 5000 }, allow_blank: true
  validates :object_identifier, uniqueness: { scope: [:investigation_case_id, :object_kind] }

  def self.attributes_from_payload(payload)
    data = normalize_payload(payload)
    {
      object_kind: data[:object_kind].to_s,
      object_identifier: data[:object_identifier].to_s,
      title: data[:title].to_s,
      summary: data[:summary].presence,
      object_type: data[:object_type].presence,
      latitude: parse_coordinate(data[:latitude]),
      longitude: parse_coordinate(data[:longitude]),
      source_context: normalize_source_context(data[:source_context]),
    }
  end

  def object_request
    { kind: object_kind, id: object_identifier }
  end

  def evidence_count
    source_context["evidence_count"].to_i
  end

  def relationship_count
    source_context["relationship_count"].to_i
  end

  def membership_count
    source_context["membership_count"].to_i
  end

  class << self
    private

    def normalize_payload(payload)
      raw =
        if payload.respond_to?(:to_unsafe_h)
          payload.to_unsafe_h
        else
          payload.to_h
        end

      raw.with_indifferent_access
    end

    def parse_coordinate(value)
      return if value.blank?

      value.to_f
    end

    def normalize_source_context(value)
      (value || {}).to_h.deep_stringify_keys
    rescue NoMethodError
      {}
    end
  end
end
