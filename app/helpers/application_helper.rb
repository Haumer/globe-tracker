module ApplicationHelper
  def globe_toggle(target: nil, action:, label:, indent: false, dot: nil, muted: false, disabled: false, category: nil, checked: false)
    css = "sb-toggle"
    css += " sb-indent" if indent
    css += " sb-muted" if muted

    input_data = { action: "change->globe##{action}" }
    input_data[:globe_target] = target if target
    input_data[:category] = category if category

    content_tag(:label, class: css) do
      concat tag.input(type: "checkbox", data: input_data, disabled: disabled, checked: checked || nil)
      concat tag.span(class: "sb-toggle-track")
      if dot
        concat content_tag(:span, class: "sb-with-dot") {
          concat tag.span(class: "sb-dot", style: "--dot: #{dot};")
          concat label
        }
      else
        concat tag.span(label)
      end
    end
  end
end
