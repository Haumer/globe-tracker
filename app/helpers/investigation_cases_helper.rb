module InvestigationCasesHelper
  def investigation_case_status_options
    InvestigationCase::STATUSES.map { |status| [status.titleize, status] }
  end

  def investigation_case_severity_options
    InvestigationCase::SEVERITIES.map { |severity| [severity.titleize, severity] }
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

  def investigation_case_object_view_href(case_object)
    object_view_path(kind: case_object.object_kind, id: case_object.object_identifier)
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
end
