require "test_helper"

class GeonamesImportServiceTest < ActiveSupport::TestCase
  # geonameid, name, asciiname, alternatenames, lat, lng, fclass, fcode,
  # country, cc2, admin1..4, population, elevation, dem, tz, moddate
  def line(id:, name:, ascii:, alt:, lat:, lng:, fcode:, cc:, pop:)
    [ id, name, ascii, alt, lat, lng, "P", fcode, cc, "", "01", "", "", "",
      pop, "", "100", "Europe/Berlin", "2026-01-01" ].join("\t") + "\n"
  end

  def write_fixture(lines)
    path = Rails.root.join("tmp", "geonames_test_#{SecureRandom.hex(4)}.txt")
    File.write(path, lines.join)
    @paths = (@paths || []) << path
    path
  end

  teardown do
    Array(@paths).each { |p| File.delete(p) if File.exist?(p) }
  end

  test "imports places with population-derived importance and country code" do
    path = write_fixture([
      line(id: "1", name: "Köln", ascii: "Koeln", alt: "Cologne,Colonia",
           lat: "50.93", lng: "6.95", fcode: "PPLA", cc: "DE", pop: "1000000"),
    ])
    GeonamesImportService.import!(path: path)

    place = Place.find_by(canonical_key: "place:geonames:1")
    assert_equal "Köln", place.name
    assert_equal "de", place.country_code
    assert_equal 1_000_000, place.population
    assert_equal "geonames", place.source
    assert_in_delta 50.93, place.latitude, 0.001
  end

  test "an imported place is reachable by native, ascii and alternate names" do
    path = write_fixture([
      line(id: "2", name: "Köln", ascii: "Koeln", alt: "Cologne,Colonia",
           lat: "50.93", lng: "6.95", fcode: "PPLA", cc: "DE", pop: "1000000"),
    ])
    GeonamesImportService.import!(path: path)

    %w[Köln Koeln Cologne Colonia koln].each do |name|
      assert_equal "place:geonames:2", Place.lookup(name).first&.canonical_key,
                   "expected #{name.inspect} to resolve"
    end
  end

  test "auto-imported places rank below the hand-curated set" do
    path = write_fixture([
      line(id: "3", name: "Metropolis", ascii: "Metropolis", alt: "",
           lat: "1.0", lng: "1.0", fcode: "PPLC", cc: "DE", pop: "30000000"),
    ])
    GeonamesImportService.import!(path: path)

    # A capital of 30M sits at the top of the imported band but still under
    # the curated floor, so a curated duplicate always wins.
    assert_operator Place.find_by(canonical_key: "place:geonames:3").importance_score, :<, 0.99
  end

  test "skips aliases too short to be safe and caps the rest" do
    path = write_fixture([
      line(id: "4", name: "Testville", ascii: "Testville",
           alt: (%w[Of Why AB] + (1..20).map { |i| "Aliasname#{i}" }).join(","),
           lat: "1.0", lng: "1.0", fcode: "PPL", cc: "DE", pop: "6000"),
    ])
    GeonamesImportService.import!(path: path)

    place = Place.find_by(canonical_key: "place:geonames:4")
    names = place.place_aliases.pluck(:normalized_name)
    assert_not_includes names, "of"
    assert_not_includes names, "why"
    assert_operator names.size, :<=, GeonamesImportService::MAX_ALIASES_PER_PLACE
  end

  test "re-importing the same file is idempotent" do
    lines = [ line(id: "5", name: "Repeatville", ascii: "Repeatville", alt: "Repeaton",
                   lat: "2.0", lng: "2.0", fcode: "PPL", cc: "FR", pop: "9000") ]
    path = write_fixture(lines)

    GeonamesImportService.import!(path: path)
    places, aliases = Place.count, PlaceAlias.count
    GeonamesImportService.import!(path: write_fixture(lines))

    assert_equal places, Place.count
    assert_equal aliases, PlaceAlias.count
  end

  test "rows without coordinates or a name are skipped" do
    path = write_fixture([
      line(id: "6", name: "", ascii: "", alt: "", lat: "1.0", lng: "1.0",
           fcode: "PPL", cc: "DE", pop: "9000"),
      line(id: "7", name: "Nowhere", ascii: "Nowhere", alt: "", lat: "0", lng: "0",
           fcode: "PPL", cc: "DE", pop: "9000"),
    ])
    GeonamesImportService.import!(path: path)

    assert_nil Place.find_by(canonical_key: "place:geonames:6")
    assert_nil Place.find_by(canonical_key: "place:geonames:7")
  end
end
