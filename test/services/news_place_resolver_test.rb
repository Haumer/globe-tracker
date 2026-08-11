require "test_helper"

class NewsPlaceResolverTest < ActiveSupport::TestCase
  setup { NewsPlaceResolver.reset_cache! }
  teardown { NewsPlaceResolver.reset_cache! }

  test "resolves a named place at a located precision" do
    result = NewsPlaceResolver.resolve(
      place_name: "Isfahan", country_code: "IR", precision: "city",
      basis: "title_place", latitude: 32.65, longitude: 51.67, confidence: 0.8
    )

    assert result.place?
    assert result.usable?
    assert_equal "Isfahan", result.name
    assert_equal "ir", result.country_code
    assert result.coordinate_trusted?
  end

  test "refuses a publisher-derived location rather than naming the newsroom" do
    %w[publisher_domain source_country_hint].each do |basis|
      result = NewsPlaceResolver.resolve(
        place_name: "La Tercera", country_code: "CL", precision: "city",
        basis: basis, latitude: -33.4, longitude: -70.6
      )

      assert result.none?, "#{basis} must not produce a place"
      assert_not result.usable?
      assert_not result.coordinate_trusted?, "#{basis} coordinates locate the newsroom"
    end
  end

  test "falls back to the country tier when only a country is known" do
    OntologyEntity.create!(canonical_key: "country:chl", entity_type: "country",
                           canonical_name: "Chile", country_code: "CL")

    result = NewsPlaceResolver.resolve(
      place_name: "CL", country_code: "CL", precision: "country",
      basis: "title_country_keyword", latitude: -35.0, longitude: -71.0
    )

    assert result.country?
    assert_equal "Chile", result.name, "should resolve to the existing country entity, not a place called CL"
    assert_equal "cl", result.country_code
  end

  test "never treats a bare country code as a place name" do
    result = NewsPlaceResolver.resolve(
      place_name: "CL", country_code: "CL", precision: "city", basis: "title_place"
    )

    assert_not result.place?, "a two-letter value is a country code in the wrong column"
    assert result.country?
  end

  test "a country-only basis cannot mint a place even at a located precision" do
    result = NewsPlaceResolver.resolve(
      place_name: "Santiago", country_code: "CL", precision: "city", basis: "ai_country"
    )

    assert result.country?, "ai_country establishes a country, not a city"
  end

  test "returns none when there is nothing trustworthy" do
    assert NewsPlaceResolver.resolve.none?
    assert NewsPlaceResolver.call(nil).none?
    assert NewsPlaceResolver.resolve(place_name: "Der Spiegel", precision: "country", basis: "publisher_domain").none?
  end

  test "reads a NewsEvent without touching its name" do
    event = OpenStruct.new(
      name: "Free Malaysia Today",
      geocode_place_name: "Kuala Lumpur", geocode_country_code: "MY",
      geocode_precision: "city", geocode_basis: "title_place",
      geocode_confidence: 0.7, latitude: 3.14, longitude: 101.69
    )

    result = NewsPlaceResolver.call(event)

    assert_equal "Kuala Lumpur", result.name
    assert_not_equal "Free Malaysia Today", result.name
  end

  test "uses the built-in country map when no country entity exists" do
    result = NewsPlaceResolver.resolve(country_code: "FR", precision: "country", basis: "ai_country")

    assert result.country?
    assert_equal "France", result.name
  end
end
