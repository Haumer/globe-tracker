require "test_helper"

class PipelineMarketContextServiceTest < ActiveSupport::TestCase
  setup do
    @pipeline = OpenStruct.new(pipeline_type: "oil")
  end

  test "TYPE_COMMODITY_KEYS maps oil to correct keys" do
    keys = PipelineMarketContextService::TYPE_COMMODITY_KEYS["oil"]

    assert_includes keys, "oil_crude"
  end

  test "TYPE_COMMODITY_KEYS maps gas to correct keys" do
    keys = PipelineMarketContextService::TYPE_COMMODITY_KEYS["gas"]

    assert_includes keys, "gas_nat"
    assert_includes keys, "lng"
  end

  test "TYPE_BENCHMARK_SYMBOLS maps oil to brent and wti" do
    symbols = PipelineMarketContextService::TYPE_BENCHMARK_SYMBOLS["oil"]

    assert_includes symbols, "OIL_BRENT"
    assert_includes symbols, "OIL_WTI"
  end

  test "call returns expected payload structure" do
    service = PipelineMarketContextService.new(@pipeline)
    result = service.call

    assert result.key?(:summary)
    assert result.key?(:risk_level)
    assert result.key?(:highlights)
    assert result.key?(:benchmarks)
    assert result.key?(:primary_benchmark_symbol)
    assert result.key?(:downstream_countries)
    assert result.key?(:route_pressure)
  end

  test "call with detail includes extra fields" do
    ChokepointSnapshotService.stub(:fetch_or_enqueue, nil) do
      service = PipelineMarketContextService.new(@pipeline, detail: true)
      result = service.call

      assert result.key?(:benchmark_series)
      assert result.key?(:coverage)
    end
  end

  test "derive_risk_level returns low for minimal data" do
    service = PipelineMarketContextService.new(@pipeline)
    level = service.send(:derive_risk_level, [], [], [])

    assert_equal "low", level
  end

  test "derive_risk_level returns critical for high scores" do
    service = PipelineMarketContextService.new(@pipeline)
    benchmarks = [{ change_pct: 5.0 }]
    downstream = [{ dependency_score: 0.9 }]
    route_pressure = [{ exposure_score: 0.85 }]

    level = service.send(:derive_risk_level, benchmarks, downstream, route_pressure)

    assert_equal "critical", level
  end

  test "derive_risk_level returns high for moderate scores" do
    service = PipelineMarketContextService.new(@pipeline)
    benchmarks = [{ change_pct: 2.0 }]
    downstream = [{ dependency_score: 0.7 }]
    route_pressure = [{ exposure_score: 0.65 }]

    level = service.send(:derive_risk_level, benchmarks, downstream, route_pressure)

    assert_equal "high", level
  end

  test "build_summary returns unavailable message when no data" do
    service = PipelineMarketContextService.new(@pipeline)
    result = service.send(:build_summary, [], [], [])

    assert_equal "Linked market context unavailable.", result
  end

  test "benchmark_summary returns nil for nil quote" do
    service = PipelineMarketContextService.new(@pipeline)
    result = service.send(:benchmark_summary, nil)

    assert_nil result
  end

  test "benchmark_summary formats change percentage" do
    service = PipelineMarketContextService.new(@pipeline)
    quote = { name: "Brent", symbol: "OIL_BRENT", change_pct: -2.5 }
    result = service.send(:benchmark_summary, quote)

    assert_match(/Brent/, result)
    assert_match(/-2\.50%/, result)
  end

  test "sampled_entries returns all entries if below threshold" do
    service = PipelineMarketContextService.new(@pipeline)
    entries = (1..10).map { |i| ["SYM", Time.current - i.hours, i.to_f] }

    result = service.send(:sampled_entries, entries)

    assert_equal 10, result.size
  end

  test "sampled_entries downsamples large arrays" do
    service = PipelineMarketContextService.new(@pipeline)
    entries = (1..100).map { |i| ["SYM", Time.current - i.hours, i.to_f] }

    result = service.send(:sampled_entries, entries)

    assert result.size <= PipelineMarketContextService::MAX_SERIES_POINTS + 1
  end

  test "sampled_entries returns empty for blank input" do
    service = PipelineMarketContextService.new(@pipeline)

    assert_equal [], service.send(:sampled_entries, [])
    assert_equal [], service.send(:sampled_entries, nil)
  end

  test "estimated_row? detects estimated flag with string key" do
    service = PipelineMarketContextService.new(@pipeline)
    row = OpenStruct.new(metadata: { "estimated" => true })

    assert service.send(:estimated_row?, row)
  end

  test "estimated_row? detects estimated flag with symbol key" do
    service = PipelineMarketContextService.new(@pipeline)
    row = OpenStruct.new(metadata: { estimated: true })

    assert service.send(:estimated_row?, row)
  end

  test "estimated_row? returns false when not estimated" do
    service = PipelineMarketContextService.new(@pipeline)
    row = OpenStruct.new(metadata: {})

    refute service.send(:estimated_row?, row)
  end
end
