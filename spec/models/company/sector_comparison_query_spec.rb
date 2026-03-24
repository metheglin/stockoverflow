require "rails_helper"

RSpec.describe Company::SectorComparisonQuery do
  describe "#build_threshold_map" do
    let(:sector_stats) do
      {
        "roe" => {
          "mean" => 0.08,
          "median" => 0.07,
          "q1" => 0.04,
          "q3" => 0.12,
          "min" => -0.05,
          "max" => 0.25,
          "stddev" => 0.06,
          "count" => 50,
        },
      }
    end

    let(:sector_map) do
      sm_a = SectorMetric.new(sector_code: "3050", data_json: sector_stats)
      sm_b = SectorMetric.new(sector_code: "5250", data_json: sector_stats)
      { "3050" => sm_a, "5250" => sm_b }
    end

    it "above_average で mean 値が閾値となる" do
      query = Company::SectorComparisonQuery.new(
        metric: :roe,
        condition: :above_average,
      )

      threshold_map = query.build_threshold_map(sector_map)

      expect(threshold_map["3050"]).to eq(0.08)
      expect(threshold_map["5250"]).to eq(0.08)
    end

    it "above_median で median 値が閾値となる" do
      query = Company::SectorComparisonQuery.new(
        metric: :roe,
        condition: :above_median,
      )

      threshold_map = query.build_threshold_map(sector_map)

      expect(threshold_map["3050"]).to eq(0.07)
      expect(threshold_map["5250"]).to eq(0.07)
    end

    it "top_quartile で q3 値が閾値となる" do
      query = Company::SectorComparisonQuery.new(
        metric: :roe,
        condition: :top_quartile,
      )

      threshold_map = query.build_threshold_map(sector_map)

      expect(threshold_map["3050"]).to eq(0.12)
    end

    it "bottom_quartile で q1 値が閾値となる" do
      query = Company::SectorComparisonQuery.new(
        metric: :roe,
        condition: :bottom_quartile,
      )

      threshold_map = query.build_threshold_map(sector_map)

      expect(threshold_map["3050"]).to eq(0.04)
    end

    it "指標の統計がないセクターがスキップされる" do
      sm_empty = SectorMetric.new(sector_code: "9050", data_json: {})
      mixed_map = sector_map.merge("9050" => sm_empty)

      query = Company::SectorComparisonQuery.new(
        metric: :roe,
        condition: :above_average,
      )

      threshold_map = query.build_threshold_map(mixed_map)

      expect(threshold_map.key?("3050")).to be true
      expect(threshold_map.key?("9050")).to be false
    end

    it "data_jsonがnilのセクターがスキップされる" do
      sm_nil = SectorMetric.new(sector_code: "9050", data_json: nil)
      mixed_map = sector_map.merge("9050" => sm_nil)

      query = Company::SectorComparisonQuery.new(
        metric: :roe,
        condition: :above_average,
      )

      threshold_map = query.build_threshold_map(mixed_map)

      expect(threshold_map.key?("9050")).to be false
    end
  end
end
