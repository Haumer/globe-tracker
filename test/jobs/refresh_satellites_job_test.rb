require "test_helper"

class RefreshSatellitesJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshSatellitesJob.new.queue_name
  end

  test "tracks polling with source celestrak and poll_type satellites" do
    assert_equal "celestrak", RefreshSatellitesJob.polling_source_resolver
    assert_equal "satellites", RefreshSatellitesJob.polling_type_resolver
  end

  test "calls CelestrakService.refresh_if_stale with nil category by default" do
    called_with = nil
    celestrak_mock = ->(**kwargs) { called_with = kwargs; 100 }

    CelestrakService.stub(:refresh_if_stale, celestrak_mock) do
      ClassifiedSatelliteEnrichmentService.stub(:enrich_all, -> { nil }) do
        RefreshSatellitesJob.perform_now
      end
    end

    assert_nil called_with[:category]
  end

  test "calls CelestrakService.refresh_if_stale with specific category" do
    called_with = nil
    celestrak_mock = ->(**kwargs) { called_with = kwargs; 50 }

    CelestrakService.stub(:refresh_if_stale, celestrak_mock) do
      RefreshSatellitesJob.perform_now("weather")
    end

    assert_equal "weather", called_with[:category]
  end

  test "enriches classified satellites when category is analyst" do
    enrichment_called = false

    CelestrakService.stub(:refresh_if_stale, ->(**_kw) { 10 }) do
      ClassifiedSatelliteEnrichmentService.stub(:enrich_all, -> { enrichment_called = true; nil }) do
        RefreshSatellitesJob.perform_now("analyst")
      end
    end

    assert enrichment_called
  end

  test "enriches classified satellites when category is nil" do
    enrichment_called = false

    CelestrakService.stub(:refresh_if_stale, ->(**_kw) { 10 }) do
      ClassifiedSatelliteEnrichmentService.stub(:enrich_all, -> { enrichment_called = true; nil }) do
        RefreshSatellitesJob.perform_now
      end
    end

    assert enrichment_called
  end

  test "does not enrich classified satellites for non-analyst categories" do
    enrichment_called = false

    CelestrakService.stub(:refresh_if_stale, ->(**_kw) { 10 }) do
      ClassifiedSatelliteEnrichmentService.stub(:enrich_all, -> { enrichment_called = true; nil }) do
        RefreshSatellitesJob.perform_now("weather")
      end
    end

    refute enrichment_called
  end
end
