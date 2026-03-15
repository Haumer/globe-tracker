require "test_helper"

class OebbTrainServiceTest < ActiveSupport::TestCase
  test "HAFAS_URL points to oebb" do
    assert_equal "https://fahrplan.oebb.at/gate", OebbTrainService::HAFAS_URL
  end

  test "bbox_to_rect converts comma string to HAFAS coordinates" do
    svc = OebbTrainService.new
    result = svc.send(:bbox_to_rect, "46.5,9.5,49.0,17.1")
    assert_equal 9_500_000, result[:llCrd][:x]
    assert_equal 46_500_000, result[:llCrd][:y]
    assert_equal 17_100_000, result[:urCrd][:x]
    assert_equal 49_000_000, result[:urCrd][:y]
  end

  test "default_rect covers Austria" do
    svc = OebbTrainService.new
    rect = svc.send(:default_rect)
    assert rect[:llCrd][:y] >= 46_000_000
    assert rect[:urCrd][:y] <= 50_000_000
  end

  test "parse_response extracts trains and skips buses" do
    svc = OebbTrainService.new
    data = {
      "svcResL" => [{
        "res" => {
          "jnyL" => [
            { "pos" => { "x" => 16_370_000, "y" => 48_210_000 }, "prodX" => 0, "jid" => "abc" },
            { "pos" => { "x" => 16_370_000, "y" => 48_210_000 }, "prodX" => 1, "jid" => "def" },
          ],
          "common" => {
            "prodL" => [
              { "name" => "RJX 163", "prodCtx" => { "catOutS" => "RJX", "catOutL" => "Railjet Xpress" } },
              { "name" => "Bus 200", "prodCtx" => { "catOutS" => "Bus", "catOutL" => "Bus" } },
            ]
          }
        }
      }]
    }

    result = svc.send(:parse_response, data)
    assert_equal 1, result.size
    assert_equal "RJX 163", result[0][:name]
  end

  test "parse_response returns empty array for nil svc" do
    svc = OebbTrainService.new
    assert_equal [], svc.send(:parse_response, { "svcResL" => [{ "res" => nil }] })
  end
end
