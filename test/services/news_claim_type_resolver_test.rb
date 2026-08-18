require "test_helper"

class NewsClaimTypeResolverTest < ActiveSupport::TestCase
  def stub(*replies)
    queue = replies.dup
    ->(_prompt) { queue.shift }
  end

  def index_of(event_type)
    NewsClaimTypeResolver::CATALOG.index { |pair| pair[:event_type] == event_type }
  end

  test "assigns the family and type the chosen catalog entry carries" do
    choice = index_of("airstrike")

    assignments = NewsClaimTypeResolver.call(
      headlines: [ "Explosions heard over Isfahan overnight" ],
      client: stub(%({"answers": [{"n": 1, "choice": #{choice}}]}))
    )

    assert_equal 1, assignments.size
    assert assignments.first.assigned?
    assert_equal "conflict", assignments.first.event_family
    assert_equal "airstrike", assignments.first.event_type
    assert assignments.first.called
  end

  # The prompt says null is expected to be the commonest answer, so it has to be
  # a decision the caller can act on rather than an absence.
  test "null is a real answer and is distinct from never being reached" do
    none = NewsClaimTypeResolver.call(
      headlines: [ "Why the Gulf still misreads Washington" ],
      client: stub('{"answers": [{"n": 1, "choice": null}]}')
    ).first

    assert_not none.assigned?
    assert none.called, "the model answered none; the caller must not treat it as a miss"
  end

  test "a dead client marks every headline in the batch unreachable" do
    assignments = NewsClaimTypeResolver.call(
      headlines: [ "One", "Two", "Three" ], client: ->(_) { nil }
    )

    assert_equal 3, assignments.size
    assert assignments.none?(&:called)
    assert assignments.none?(&:assigned?)
  end

  # The model cannot widen the taxonomy. An index past the end is it inventing a
  # kind the clusterer has no window or max-distance for.
  test "an out of range choice is none, not a guess" do
    over = NewsClaimTypeResolver.call(
      headlines: [ "Anything" ],
      client: stub(%({"answers": [{"n": 1, "choice": #{NewsClaimTypeResolver::CATALOG.size}}]}))
    ).first
    under = NewsClaimTypeResolver.call(
      headlines: [ "Anything" ], client: stub('{"answers": [{"n": 1, "choice": -1}]}')
    ).first

    assert_not over.assigned?
    assert_not under.assigned?
  end

  # The failure this design exists to prevent. Read positionally, a reply that
  # skips an item files every later headline under the wrong event -- and the
  # counts all still add up, so nothing downstream would show it.
  test "a short reply does not shift the answers after the gap" do
    quake = index_of("earthquake")
    assignments = NewsClaimTypeResolver.call(
      headlines: [ "Commentary on the summit", "Quake rattles the coast", "Another opinion piece" ],
      client: stub(%({"answers": [{"n": 2, "choice": #{quake}}]}))
    )

    assert_equal 3, assignments.size
    assert_not assignments[0].assigned?
    assert_equal "earthquake", assignments[1].event_type
    assert_not assignments[2].assigned?
  end

  test "answers out of order land on the headline they name" do
    flood = index_of("flood")
    protest = index_of("protest")

    assignments = NewsClaimTypeResolver.call(
      headlines: [ "Crowds fill the square", "River bursts its banks" ],
      client: stub(%({"answers": [{"n": 2, "choice": #{flood}}, {"n": 1, "choice": #{protest}}]}))
    )

    assert_equal "protest", assignments[0].event_type
    assert_equal "flood", assignments[1].event_type
  end

  test "a duplicated n keeps the first answer rather than overwriting" do
    flood = index_of("flood")
    quake = index_of("earthquake")

    assignment = NewsClaimTypeResolver.call(
      headlines: [ "River bursts its banks" ],
      client: stub(%({"answers": [{"n": 1, "choice": #{flood}}, {"n": 1, "choice": #{quake}}]}))
    ).first

    assert_equal "flood", assignment.event_type
  end

  test "an unparseable reply is none for the batch rather than an exception" do
    assignments = NewsClaimTypeResolver.call(
      headlines: [ "One", "Two" ], client: stub("the model apologises at length")
    )

    assert_equal 2, assignments.size
    assert assignments.none?(&:assigned?)
    assert assignments.all?(&:called)
  end

  test "headlines beyond the batch size are split across calls and stay in order" do
    quake = index_of("earthquake")
    size = NewsClaimTypeResolver::BATCH_SIZE
    headlines = Array.new(size + 1) { |index| "Headline #{index}" }

    calls = 0
    client = lambda do |_prompt|
      calls += 1
      # Answers the first item of whichever slice it is handed.
      %({"answers": [{"n": 1, "choice": #{quake}}]})
    end

    assignments = NewsClaimTypeResolver.call(headlines: headlines, client: client)

    assert_equal 2, calls
    assert_equal size + 1, assignments.size
    assert_equal "earthquake", assignments[0].event_type
    assert_not assignments[1].assigned?
    assert_equal "earthquake", assignments[size].event_type, "the second slice's first item"
  end

  # The catalog is what makes an invented family impossible. If it ever contained
  # the fallthrough values, the resolver could assign exactly what the clusterer
  # drops and the whole arm would be a no-op that still cost money.
  test "the catalog only offers kinds the clusterer accepts" do
    assert NewsClaimTypeResolver::CATALOG.any?

    NewsClaimTypeResolver::CATALOG.each do |pair|
      assert_includes NewsStoryClusterer::CLUSTERABLE_EVENT_FAMILIES, pair[:event_family]
      assert_not_includes NewsStoryClusterer::GENERAL_EVENT_TYPES, pair[:event_type]
    end

    assert_equal NewsClaimTypeResolver::CATALOG.uniq.size, NewsClaimTypeResolver::CATALOG.size
  end

  # What makes the added kinds safe to introduce: each inherits a tuned window
  # and max distance from a family that already has them, and none is in a
  # compatibility group, so it scores 1.0 against its own kind and 0.0 against
  # everything else. A supplementary kind cannot widen an existing cluster.
  test "supplementary kinds inherit tuned constants and cluster only with themselves" do
    NewsClaimTypeResolver::SUPPLEMENTARY_KINDS.each do |pair|
      assert NewsStoryClusterer::FAMILY_WINDOWS.key?(pair[:event_family]),
        "#{pair[:event_family]} has no tuned window"
      assert NewsStoryClusterer::FAMILY_MAX_DISTANCE_KM.key?(pair[:event_family]),
        "#{pair[:event_family]} has no tuned max distance"
      assert NewsStoryClusterer::COMPATIBLE_EVENT_GROUPS.none? { |group| group.include?(pair[:event_type]) },
        "#{pair[:event_type]} would merge into an existing type's cluster"
    end
  end

  test "the rule derived half of the catalog still tracks the extractor" do
    rule_types = NewsClaimExtractor::EVENT_RULES.map { |rule| rule[:event_type] }.uniq
    catalog_types = NewsClaimTypeResolver::CATALOG.map { |pair| pair[:event_type] }

    (rule_types - NewsStoryClusterer::GENERAL_EVENT_TYPES).each do |event_type|
      next unless NewsClaimExtractor::EVENT_RULES
        .any? { |r| r[:event_type] == event_type && NewsStoryClusterer::CLUSTERABLE_EVENT_FAMILIES.include?(r[:event_family]) }

      assert_includes catalog_types, event_type
    end
  end

  test "the prompt offers every catalog entry and asks for one line per headline" do
    prompt = NewsClaimTypeResolver.prompt_for([ "First headline", "Second headline" ])

    assert_includes prompt, "0. #{NewsClaimTypeResolver::CATALOG.first[:event_family]}"
    assert_includes prompt, "1. First headline"
    assert_includes prompt, "2. Second headline"
    assert_includes prompt, "null"
  end

  test "an empty list never reaches the model" do
    assert_equal [], NewsClaimTypeResolver.call(headlines: [], client: ->(_) { flunk "called" })
  end
end
