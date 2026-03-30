module ApplicationHelper
  def meta_title
    meta_tags[:title]
  end

  def meta_description
    meta_tags[:description]
  end

  def meta_image_url
    absolute_public_url(meta_tags[:image_path])
  end

  def meta_url
    request.original_url
  end

  def meta_tags
    @meta_tags ||= begin
      defaults = {
        title: "GlobeTracker | Live Global Tracking",
        description: "Live global tracking for conflict events, conflict theaters, infrastructure, flights, ships, news, and cross-layer insights.",
        image_path: "/og-card.png",
        image_alt: "GlobeTracker live intelligence globe",
        type: "website",
        site_name: "GlobeTracker",
      }

      page_specific = case [controller_name, action_name]
      when [ "pages", "landing" ]
        {
          title: "GlobeTracker | Geospatial Intelligence Workspace",
          description: "A live geospatial intelligence workspace for aviation, maritime, infrastructure, conflict, and cross-layer analysis.",
        }
      when [ "pages", "sources" ]
        {
          title: "Sources | GlobeTracker",
          description: "Inspect the live source inventory and data coverage powering GlobeTracker.",
        }
      when [ "pages", "about" ]
        {
          title: "About | GlobeTracker",
          description: "Learn how GlobeTracker fuses live events, infrastructure, tracking, and intelligence signals into one operational globe.",
        }
      when [ "objects", "show" ]
        {
          title: [ @meta_title.presence, "GlobeTracker" ].compact.join(" | "),
          description: @meta_description.presence || "Inspect linked evidence, relationships, and geographic context for this GlobeTracker object.",
        }
      else
        {}
      end

      overrides = {
        title: @meta_title.presence,
        description: @meta_description.presence,
        image_path: @meta_image_path.presence,
        image_alt: @meta_image_alt.presence,
        type: @meta_type.presence,
      }.compact

      defaults.merge(page_specific).merge(overrides)
    end
  end

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

  def globe_map_href
    return area_workspace_globe_href(@area_workspace) if defined?(@area_workspace) && @area_workspace.present? && respond_to?(:area_workspace_globe_href)

    root_path
  end

  private

  def absolute_public_url(path)
    return path if path.to_s.start_with?("http://", "https://")

    host = request&.base_url.presence ||
      begin
        configured = ENV["APP_HOST"].presence
        configured.present? ? (configured.start_with?("http://", "https://") ? configured : "https://#{configured}") : nil
      end ||
      "https://globe.haumer.ai"

    "#{host}#{path}"
  end
end
