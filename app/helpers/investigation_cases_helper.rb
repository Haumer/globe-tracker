module InvestigationCasesHelper
  def investigation_case_status_options
    InvestigationCase::STATUSES.map { |status| [status.titleize, status] }
  end

  def investigation_case_severity_options
    InvestigationCase::SEVERITIES.map { |severity| [severity.titleize, severity] }
  end

  def investigation_case_note_kind_options
    InvestigationCaseNote::NOTE_KINDS.map { |kind| [kind.titleize, kind] }
  end

  def investigation_case_status_label(value)
    value.to_s.tr("_", " ").titleize
  end

  def investigation_case_severity_label(value)
    value.to_s.tr("_", " ").titleize
  end

  def investigation_case_status_class(value)
    "case-badge--#{value.to_s.parameterize}"
  end

  def investigation_case_severity_class(value)
    "case-badge--#{value.to_s.parameterize}"
  end

  def investigation_case_note_kind_class(value)
    "case-badge--#{value.to_s.parameterize}"
  end

  def investigation_case_object_view_href(case_object)
    object_view_path(kind: case_object.object_kind, id: case_object.object_identifier)
  end

  def investigation_case_object_viewable?(case_object)
    %w[chokepoint theater news_story_cluster commodity entity].include?(case_object.object_kind.to_s)
  end

  def investigation_case_object_globe_href(case_object)
    options = {
      focus_kind: case_object.object_kind,
      focus_id: case_object.object_identifier,
      focus_title: case_object.title,
    }

    if case_object.latitude.present? && case_object.longitude.present?
      options[:anchor] = [
        case_object.latitude.to_f.round(4),
        case_object.longitude.to_f.round(4),
        2500000,
        0,
        -1.25,
      ].join(",")
    end

    root_path(options)
  end

  def investigation_case_source_hidden_fields(source_object)
    return "".html_safe if source_object.blank?

    tags = []
    source_object.except(:source_context).each do |key, value|
      next if value.blank?

      tags << hidden_field_tag("source_object[#{key}]", value)
    end
    source_object.fetch(:source_context, {}).each do |key, value|
      next if value.blank?

      tags << hidden_field_tag("source_object[source_context][#{key}]", value)
    end
    safe_join(tags)
  end

  def investigation_case_assignable_user_options(assignable_users, selected_id = nil)
    options_for_select(
      [["Unassigned", nil]] + assignable_users.map { |user| [user.email, user.id] },
      selected_id
    )
  end
end
