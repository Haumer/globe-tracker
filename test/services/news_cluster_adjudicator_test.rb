require "test_helper"

class NewsClusterAdjudicatorTest < ActiveSupport::TestCase
  def candidate(titles, location: "Jizan", actors: [ "Houthis" ])
    {
      titles: titles, location_name: location, actors: actors,
      first_seen_at: Time.utc(2026, 3, 24, 12, 0, 0),
      last_seen_at: Time.utc(2026, 3, 24, 18, 0, 0),
    }
  end

  def stub(reply)
    ->(_prompt) { reply }
  end

  test "files the article against the chosen cluster" do
    verdict = NewsClusterAdjudicator.call(
      title: "Aramco refinery erupts in flames in Jizan",
      candidates: [ candidate([ "Nagasaki marks bombing anniversary" ]), candidate([ "Fire at Saudi refinery" ]) ],
      client: stub('{"choice": 1, "reason": "same refinery fire"}')
    )

    assert verdict.chose?
    assert_equal 1, verdict.index
    assert verdict.called
  end

  test "none is a real answer, and a different one from not being reached" do
    none = NewsClusterAdjudicator.call(
      title: "Japan wine scene comes of age",
      candidates: [ candidate([ "Fire at Saudi refinery" ]) ],
      client: stub('{"choice": null}')
    )

    assert_not none.chose?
    assert none.called, "the model answered none; the caller must not fall back"
  end

  # The distinction the caller depends on: an unreachable model leaves the
  # decision where it was before the model existed, while "none" is a decision.
  test "a dead client reports that it was never reached" do
    verdict = NewsClusterAdjudicator.call(
      title: "Anything", candidates: [ candidate([ "Fire at Saudi refinery" ]) ], client: ->(_) { nil }
    )

    assert_not verdict.chose?
    assert_not verdict.called
  end

  # The failure that actually happened: 203 of 1,273 adjudications on the
  # establishing rebuild were refused connections, and each one silently became
  # a merge. A refused connection is transient, and it is an exception rather
  # than a status code -- retrying only on 429/5xx would have caught none of it.
  # The request block runs with the stub as self, so it can close over locals
  # but must never call a helper on the test case.
  def stub_http(&request)
    http = Object.new
    %i[use_ssl= open_timeout= read_timeout=].each { |setter| http.define_singleton_method(setter) { |_| } }
    http.define_singleton_method(:request, &request)
    http
  end

  def ok_response(content)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) { { choices: [ { message: { content: content } } ] }.to_json }
    response
  end

  def with_api_key(&block)
    env = ->(key) { key == "OPENAI_API_KEY" ? "test-key" : ENV.fetch(key, nil) }
    ENV.stub(:[], env) { NewsClusterAdjudicator.stub(:sleep, nil, &block) }
  end

  test "connection refusals are retried rather than read as a decision" do
    attempts = 0
    success = ok_response('{"choice": 0}')
    http = stub_http do |_request|
      attempts += 1
      raise Errno::ECONNREFUSED if attempts < 3

      success
    end

    reply = nil
    with_api_key { Net::HTTP.stub(:new, http) { reply = NewsClusterAdjudicator.send(:chat, "prompt") } }

    assert_equal 3, attempts, "a refused connection must be retried, not surrendered to"
    assert_includes reply.to_s, "choice"
  end

  test "gives up rather than retrying forever" do
    attempts = 0
    http = stub_http { |_request| attempts += 1; raise Errno::ECONNREFUSED }

    reply = nil
    with_api_key { Net::HTTP.stub(:new, http) { reply = NewsClusterAdjudicator.send(:chat, "prompt") } }

    assert_equal NewsClusterAdjudicator::MAX_ATTEMPTS, attempts
    assert_nil reply, "exhausted retries report not-reached, which the caller reads as a fallback"
  end

  test "a rate limit is retried on the same policy as a refused connection" do
    attempts = 0
    success = ok_response('{"choice": null}')
    limited = Net::HTTPTooManyRequests.new("1.1", "429", "Too Many Requests")
    limited.define_singleton_method(:body) { "slow down" }
    http = stub_http do |_request|
      attempts += 1
      attempts >= 2 ? success : limited
    end

    with_api_key { Net::HTTP.stub(:new, http) { NewsClusterAdjudicator.send(:chat, "prompt") } }

    assert_equal 2, attempts
  end

  test "retriable errors and statuses share one policy" do
    assert_includes NewsClusterAdjudicator::RETRIABLE_ERRORS, Errno::ECONNREFUSED
    assert_includes NewsClusterAdjudicator::RETRIABLE_ERRORS, Net::ReadTimeout
    assert_includes NewsClusterAdjudicator::RETRIABLE_STATUSES, Net::HTTPTooManyRequests
    assert_operator NewsClusterAdjudicator::MAX_ATTEMPTS, :>, 1
  end

  test "treats an out-of-range choice as none" do
    verdict = NewsClusterAdjudicator.call(
      title: "Anything", candidates: [ candidate([ "Fire at Saudi refinery" ]) ], client: stub('{"choice": 7}')
    )

    assert_not verdict.chose?
    assert verdict.called
  end

  test "survives unparseable output" do
    verdict = NewsClusterAdjudicator.call(
      title: "Anything", candidates: [ candidate([ "Fire" ]) ], client: stub("probably the first one")
    )

    assert_not verdict.chose?
  end

  test "asks nothing when there is nothing to choose between" do
    called = false
    NewsClusterAdjudicator.call(title: "Anything", candidates: [], client: ->(_) { called = true })

    assert_not called
  end

  # The cluster's identity is the set of reports in it, not its first row, so
  # the prompt has to show more than the lead -- and has to say how many it is
  # not showing rather than silently truncating.
  test "prompt shows members, place, actors and span" do
    titles = (1..9).map { |n| "Report number #{n}" }
    prompt = NewsClusterAdjudicator.prompt_for("Incoming headline", [ candidate(titles) ])

    assert_includes prompt, "Article: Incoming headline"
    assert_includes prompt, "0. place: Jizan"
    assert_includes prompt, "actors: Houthis"
    assert_includes prompt, "Report number 1"
    assert_includes prompt, "Report number #{NewsClusterAdjudicator::MEMBER_PREVIEW}"
    assert_includes prompt, "(#{titles.size - NewsClusterAdjudicator::MEMBER_PREVIEW} more)"
    assert_includes prompt, "+6h"
  end

  # NewsPlaceResolver returns nothing rather than a masthead, so a cluster with
  # no resolved place is normal and the prompt must say that plainly instead of
  # rendering an empty detail line the model has to interpret.
  test "prompt says so when a cluster has nothing resolved but its headlines" do
    prompt = NewsClusterAdjudicator.prompt_for(
      "Incoming", [ { titles: [ "A report" ], location_name: nil, actors: [], first_seen_at: nil } ]
    )

    assert_includes prompt, "no place or actors resolved"
    assert_includes prompt, "A report"
  end
end
