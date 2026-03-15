require "test_helper"

class HafasTrainServiceTest < ActiveSupport::TestCase
  test "RAIL_CATEGORIES contains expected types" do
    assert HafasTrainService::RAIL_CATEGORIES.include?("ICE")
    assert HafasTrainService::RAIL_CATEGORIES.include?("IC")
    assert HafasTrainService::RAIL_CATEGORIES.include?("RE")
    assert HafasTrainService::RAIL_CATEGORIES.include?("S")
    assert_not HafasTrainService::RAIL_CATEGORIES.include?("BUS")
  end

  test "OPERATORS contains oebb configuration" do
    assert HafasTrainService::OPERATORS.key?(:oebb)
    config = HafasTrainService::OPERATORS[:oebb]
    assert_equal "AT", config[:flag]
    assert config[:url].include?("oebb.at")
  end

  test "bbox_to_rect converts comma string to HAFAS rect format" do
    svc = HafasTrainService.new
    result = svc.send(:bbox_to_rect, "46.0,9.0,49.0,17.0")
    assert_equal({ x: 9_000_000, y: 46_000_000 }, result[:llCrd])
    assert_equal({ x: 17_000_000, y: 49_000_000 }, result[:urCrd])
  end

  test "parse_response extracts trains filtering by RAIL_CATEGORIES" do
    svc = HafasTrainService.new
    data = {
      "svcResL" => [{
        "res" => {
          "jnyL" => [
            { "pos" => { "x" => 16_370_000, "y" => 48_210_000 }, "prodX" => 0, "jid" => "j1", "dirTxt" => "Wien" },
            { "pos" => { "x" => 16_370_000, "y" => 48_210_000 }, "prodX" => 1, "jid" => "j2", "dirTxt" => "Graz" },
          ],
          "common" => {
            "prodL" => [
              { "name" => "ICE 123", "prodCtx" => { "catOutS" => "ICE", "catOutL" => "InterCityExpress" } },
              { "name" => "Bus 42", "prodCtx" => { "catOutS" => "BUS", "catOutL" => "Bus" } },
            ]
          }
        }
      }]
    }

    result = svc.send(:parse_response, data, :oebb, HafasTrainService::OPERATORS[:oebb])
    assert_equal 1, result.size
    assert_equal "ICE 123", result[0][:name]
    assert_in_delta 48.21, result[0][:lat], 0.01
  end
end
