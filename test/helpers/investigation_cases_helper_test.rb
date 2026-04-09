require "test_helper"

class InvestigationCasesHelperTest < ActionView::TestCase
  include InvestigationCasesHelper

  test "investigation_case_status_options returns titleized pairs" do
    options = investigation_case_status_options
    assert_kind_of Array, options
    assert options.any? { |label, value| label == "Open" && value == "open" }
    assert options.any? { |label, value| label == "Closed" && value == "closed" }
  end

  test "investigation_case_severity_options returns titleized pairs" do
    options = investigation_case_severity_options
    assert_kind_of Array, options
    assert options.any? { |label, value| label == "Low" && value == "low" }
    assert options.any? { |label, value| label == "Critical" && value == "critical" }
  end

  test "investigation_case_note_kind_options returns titleized pairs" do
    options = investigation_case_note_kind_options
    assert_kind_of Array, options
    assert options.any? { |label, value| label == "Note" && value == "note" }
    assert options.any? { |label, value| label == "Brief" && value == "brief" }
  end

  test "investigation_case_status_label titleizes value" do
    assert_equal "Open", investigation_case_status_label("open")
    assert_equal "In Progress", investigation_case_status_label("in_progress")
  end

  test "investigation_case_severity_label titleizes value" do
    assert_equal "High", investigation_case_severity_label("high")
  end

  test "investigation_case_status_class returns parameterized CSS class" do
    assert_equal "case-badge--open", investigation_case_status_class("open")
    assert_equal "case-badge--escalated", investigation_case_status_class("escalated")
  end

  test "investigation_case_severity_class returns parameterized CSS class" do
    assert_equal "case-badge--critical", investigation_case_severity_class("critical")
  end

  test "investigation_case_note_kind_class returns parameterized CSS class" do
    assert_equal "case-badge--note", investigation_case_note_kind_class("note")
    assert_equal "case-badge--decision", investigation_case_note_kind_class("decision")
  end

  test "investigation_case_object_viewable? returns true for known kinds" do
    %w[chokepoint theater news_story_cluster commodity entity].each do |kind|
      obj = OpenStruct.new(object_kind: kind)
      assert investigation_case_object_viewable?(obj), "Expected #{kind} to be viewable"
    end
  end

  test "investigation_case_object_viewable? returns false for unknown kinds" do
    obj = OpenStruct.new(object_kind: "flight")
    assert_not investigation_case_object_viewable?(obj)
  end

  test "investigation_case_return_globe_href returns root for blank input" do
    assert_equal "/", investigation_case_return_globe_href(nil)
    assert_equal "/", investigation_case_return_globe_href("")
  end

  test "investigation_case_return_globe_href returns path for valid relative URL" do
    assert_equal "/some/path", investigation_case_return_globe_href("/some/path")
  end

  test "investigation_case_return_globe_href rejects protocol-relative URLs" do
    assert_equal "/", investigation_case_return_globe_href("//evil.com")
  end

  test "investigation_case_source_context_label returns titleized trend" do
    ctx = { escalation_trend: "rapidly_escalating" }
    assert_equal "Rapidly Escalating", investigation_case_source_context_label(ctx)
  end

  test "investigation_case_source_context_label falls back to severity" do
    ctx = { severity: "high" }
    assert_equal "High", investigation_case_source_context_label(ctx)
  end

  test "investigation_case_source_context_label returns nil when blank" do
    assert_nil investigation_case_source_context_label({})
  end

  test "investigation_case_theater_brief_state returns nil for nil workspace" do
    assert_nil investigation_case_theater_brief_state(nil)
  end

  test "investigation_case_theater_brief_state returns message for ready status" do
    ws = { theater_brief_status: "ready", theater_brief_generated_at: 1.hour.ago }
    result = investigation_case_theater_brief_state(ws)
    assert result.include?("Stored AI brief")
  end

  test "investigation_case_theater_brief_state returns pending message" do
    ws = { theater_brief_status: "pending" }
    assert_equal "Refreshing stored AI brief", investigation_case_theater_brief_state(ws)
  end

  test "investigation_case_theater_brief_state returns error message" do
    ws = { theater_brief_status: "error" }
    assert_equal "Stored AI brief unavailable", investigation_case_theater_brief_state(ws)
  end

  test "investigation_case_theater_brief_state returns nil for idle" do
    ws = { theater_brief_status: "idle" }
    assert_nil investigation_case_theater_brief_state(ws)
  end

  test "investigation_case_timeline_badge_class returns parameterized class" do
    assert_equal "case-badge--update", investigation_case_timeline_badge_class("update")
  end

  test "investigation_case_signal_badge_class returns verified class" do
    assert_equal "case-badge--signal-verified", investigation_case_signal_badge_class("verified")
  end

  test "investigation_case_signal_badge_class returns thermal class for other" do
    assert_equal "case-badge--signal-thermal", investigation_case_signal_badge_class("thermal")
    assert_equal "case-badge--signal-thermal", investigation_case_signal_badge_class("unknown")
  end

  test "investigation_case_source_hidden_fields returns empty for blank" do
    assert_equal "", investigation_case_source_hidden_fields(nil)
    assert_equal "", investigation_case_source_hidden_fields({})
  end

  test "investigation_case_source_hidden_fields generates hidden fields" do
    payload = { object_kind: "theater", object_identifier: "ukraine", title: "Ukraine", source_context: { severity: "high" } }
    html = investigation_case_source_hidden_fields(payload)
    assert html.include?("source_object[object_kind]")
    assert html.include?("theater")
    assert html.include?("source_object[source_context][severity]")
    assert html.include?("high")
  end
end
