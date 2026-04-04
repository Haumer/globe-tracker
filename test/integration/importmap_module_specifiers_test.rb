require "test_helper"

class ImportmapModuleSpecifiersTest < ActiveSupport::TestCase
  PINNED_JS_ROOTS = %w[
    app/javascript/channels
    app/javascript/controllers
    app/javascript/globe
  ].freeze

  RELATIVE_IMPORT_PATTERN = /\bfrom\s+["'](?:\.{1,2}\/)|\bimport\(\s*["'](?:\.{1,2}\/)/

  test "pinned javascript modules use importmap specifiers instead of relative imports" do
    offenders = PINNED_JS_ROOTS.flat_map do |root|
      Dir.glob(Rails.root.join(root, "**/*.js")).filter_map do |path|
        line_number = File.foreach(path).with_index(1).find { |line, _number| line.match?(RELATIVE_IMPORT_PATTERN) }&.last
        next unless line_number

        "#{Pathname(path).relative_path_from(Rails.root)}:#{line_number}"
      end
    end

    assert offenders.empty?, <<~MSG
      Relative module imports break importmap asset resolution in production.
      Use pinned specifiers like "globe/controller/foo" instead.

      Offending files:
      #{offenders.join("\n")}
    MSG
  end
end
