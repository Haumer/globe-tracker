require "test_helper"

class SubmarineCableProximityIndexTest < ActiveSupport::TestCase
  Cable = Struct.new(:name, :points)

  def build(*cables)
    SubmarineCableProximityIndex.build(cables, &:points)
  end

  test "finds the nearest cable vertex inside the search radius" do
    gulf = Cable.new("Gulf Data Link", [[26.56, 56.29]])
    med = Cable.new("Med Loop", [[35.0, 18.0]])
    index = build(gulf, med)

    match = index.nearest(26.61, 56.30, within_km: 10.0)

    assert_equal gulf, match.cable
    assert_in_delta 5.6, match.distance_km, 0.2
  end

  test "returns nil when no vertex is within the radius" do
    index = build(Cable.new("Gulf Data Link", [[26.56, 56.29]]))

    assert_nil index.nearest(27.5, 56.30, within_km: 10.0)
  end

  test "picks the closest of several vertices across cell boundaries" do
    # 26.999 and 27.001 sit in different one-degree cells; the lookup must
    # still see both and prefer the nearer one.
    near = Cable.new("Near", [[27.001, 56.0]])
    far = Cable.new("Far", [[26.95, 56.0]])
    index = build(far, near)

    match = index.nearest(26.999, 56.0, within_km: 10.0)

    assert_equal near, match.cable
  end

  test "wraps across the antimeridian" do
    index = build(Cable.new("Pacific", [[-17.0, 179.98]]))

    match = index.nearest(-17.0, -179.98, within_km: 10.0)

    assert_equal "Pacific", match.cable.name
    assert_in_delta 4.3, match.distance_km, 0.2
  end

  test "agrees with a brute-force scan" do
    rng = Random.new(7)
    cables = 40.times.map do |i|
      Cable.new("c#{i}", 25.times.map { [rng.rand(-70.0..70.0), rng.rand(-180.0..180.0)] })
    end
    index = build(*cables)
    radians = Math::PI / 180.0
    haversine = lambda do |lat1, lng1, lat2, lng2|
      dlat = (lat2 - lat1) * radians
      dlng = (lng2 - lng1) * radians
      a = Math.sin(dlat / 2)**2 + Math.cos(lat1 * radians) * Math.cos(lat2 * radians) * Math.sin(dlng / 2)**2
      6371.0 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    end

    200.times do
      # Probe near a known vertex so some lookups hit and some miss.
      base = cables.sample(random: rng).points.sample(random: rng)
      lat = base[0] + rng.rand(-0.3..0.3)
      lng = base[1] + rng.rand(-0.3..0.3)

      expected = cables.flat_map { |c| c.points.map { |p| [c, haversine.call(p[0], p[1], lat, lng)] } }
        .select { |_, d| d <= 25.0 }.min_by { |_, d| d }
      actual = index.nearest(lat, lng, within_km: 25.0)

      if expected.nil?
        assert_nil actual
      else
        assert_equal expected[0], actual.cable
        assert_in_delta expected[1], actual.distance_km, 1e-9
      end
    end
  end

  test "an empty index answers nil" do
    assert_nil build.nearest(0.0, 0.0, within_km: 10.0)
  end
end
