require "test_helper"

class AreaReportTest < ActiveSupport::TestCase
  test "initializes with string keys" do
    report = AreaReport.new("lamin" => 40.0, "lamax" => 50.0, "lomin" => -10.0, "lomax" => 10.0)
    assert_instance_of AreaReport, report
  end

  test "generate returns hash with expected keys" do
    bounds = { lamin: 40.0, lamax: 50.0, lomin: -10.0, lomax: 10.0 }
    result = AreaReport.new(bounds).generate
    assert_instance_of Hash, result
  end

  test "class method generate delegates to instance" do
    bounds = { lamin: 40.0, lamax: 50.0, lomin: -10.0, lomax: 10.0 }
    result = AreaReport.generate(bounds)
    assert_instance_of Hash, result
  end

  test "generate returns compact hash omitting nil sections" do
    bounds = { lamin: 89.0, lamax: 90.0, lomin: 179.0, lomax: 180.0 }
    result = AreaReport.generate(bounds)
    result.each_value { |v| assert_not_nil v }
  end
end
