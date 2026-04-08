require "test_helper"

class MaritimePassageSignalExtractorTest < ActiveSupport::TestCase
  test "extracts restricted selective passage signals" do
    signal = MaritimePassageSignalExtractor.extract(
      title: "Iran considers transit fees in Hormuz",
      summary: "Officials described permission-based passage and toll-like controls for some vessels."
    )

    assert_equal :restricted_selective, signal[:state]
    assert_includes signal[:signals], "transit_fee"
    assert_includes signal[:signals], "permission_required"
  end

  test "returns nil for unrelated text" do
    signal = MaritimePassageSignalExtractor.extract(
      title: "Quarterly shipping earnings improved",
      summary: "Carriers reported better margins and steadier fuel costs."
    )

    assert_nil signal
  end

  test "extracts safe passage signals as open transit" do
    signal = MaritimePassageSignalExtractor.extract(
      title: "Iran agrees to safe passage through Strait of Hormuz",
      summary: "Officials said the route is open to ships for two weeks after the ceasefire."
    )

    assert_equal :open, signal[:state]
    assert_includes signal[:signals], "safe_passage"
  end
end
