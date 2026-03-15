require "test_helper"

class CircuitBreakerTest < ActiveSupport::TestCase
  setup do
    CircuitBreaker.reset!
  end

  test "state_for returns CLOSED for unknown key" do
    assert_equal CircuitBreaker::CLOSED, CircuitBreaker.state_for("unknown_key")
  end

  test "record_failure transitions CLOSED to OPEN after threshold" do
    (CircuitBreaker::FAILURE_THRESHOLD - 1).times { CircuitBreaker.record_failure("svc") }
    assert_equal CircuitBreaker::CLOSED, CircuitBreaker.state_for("svc")

    CircuitBreaker.record_failure("svc")
    assert_equal CircuitBreaker::OPEN, CircuitBreaker.state_for("svc")
  end

  test "OPEN transitions to HALF_OPEN after OPEN_DURATION" do
    CircuitBreaker::FAILURE_THRESHOLD.times { CircuitBreaker.record_failure("svc2") }
    assert_equal CircuitBreaker::OPEN, CircuitBreaker.state_for("svc2")

    travel CircuitBreaker::OPEN_DURATION + 1.second do
      assert_equal CircuitBreaker::HALF_OPEN, CircuitBreaker.state_for("svc2")
    end
  end

  test "record_success in HALF_OPEN transitions to CLOSED" do
    CircuitBreaker::FAILURE_THRESHOLD.times { CircuitBreaker.record_failure("svc3") }

    travel CircuitBreaker::OPEN_DURATION + 1.second do
      CircuitBreaker.state_for("svc3") # triggers HALF_OPEN
      CircuitBreaker.record_success("svc3")
      assert_equal CircuitBreaker::CLOSED, CircuitBreaker.state_for("svc3")
    end
  end

  test "record_failure in HALF_OPEN transitions back to OPEN" do
    CircuitBreaker::FAILURE_THRESHOLD.times { CircuitBreaker.record_failure("svc4") }

    travel CircuitBreaker::OPEN_DURATION + 1.second do
      CircuitBreaker.state_for("svc4") # triggers HALF_OPEN
      CircuitBreaker.record_failure("svc4")
      assert_equal CircuitBreaker::OPEN, CircuitBreaker.state_for("svc4")
    end
  end

  test "circuit_key_for builds key from URI" do
    obj = Object.new
    obj.extend(CircuitBreaker)
    uri = URI("https://api.example.com/v2/data")
    assert_equal "api.example.com/v2/data", obj.circuit_key_for(uri)
  end
end
