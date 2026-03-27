require "rails_helper"

RSpec.describe TrendTurningPoint do
  def build_metric(attrs = {})
    defaults = {
      id: 1,
      company_id: 1,
      fiscal_year_end: Date.new(2025, 3, 31),
      scope: :consolidated,
      period_type: :annual,
    }
    FinancialMetric.new(defaults.merge(attrs))
  end

  describe ".detect_growth_resumption" do
    it "0→1の増収転換でgrowth_resumptionが検出される" do
      current = build_metric(consecutive_revenue_growth: 1, revenue_yoy: BigDecimal("0.05"))
      prev = build_metric(
        id: 2,
        fiscal_year_end: Date.new(2024, 3, 31),
        consecutive_revenue_growth: 0,
        revenue_yoy: BigDecimal("-0.03"),
      )

      result = TrendTurningPoint.detect_growth_resumption(current, [prev])
      expect(result.size).to eq(1)
      expect(result.first[:pattern_type]).to eq(:growth_resumption)
    end

    it "前期も増収の場合は検出されない" do
      current = build_metric(consecutive_revenue_growth: 3)
      prev = build_metric(
        id: 2,
        fiscal_year_end: Date.new(2024, 3, 31),
        consecutive_revenue_growth: 2,
      )

      result = TrendTurningPoint.detect_growth_resumption(current, [prev])
      expect(result).to be_empty
    end

    it "2期連続減収後の回復ではhigh significanceになる" do
      current = build_metric(consecutive_revenue_growth: 1, revenue_yoy: BigDecimal("0.05"))
      prev = build_metric(
        id: 2,
        fiscal_year_end: Date.new(2024, 3, 31),
        consecutive_revenue_growth: 0,
        revenue_yoy: BigDecimal("-0.05"),
      )
      prev2 = build_metric(
        id: 3,
        fiscal_year_end: Date.new(2023, 3, 31),
        consecutive_revenue_growth: 0,
        revenue_yoy: BigDecimal("-0.08"),
      )

      result = TrendTurningPoint.detect_growth_resumption(current, [prev, prev2])
      expect(result.first[:significance]).to eq(:high)
    end
  end

  describe ".detect_free_cf_turnaround" do
    it "FCF false→trueでfree_cf_turnaroundが検出される" do
      current = build_metric(free_cf_positive: true, free_cf: 500_000)
      prev = build_metric(
        id: 2,
        fiscal_year_end: Date.new(2024, 3, 31),
        free_cf_positive: false,
        free_cf: -200_000,
      )

      result = TrendTurningPoint.detect_free_cf_turnaround(current, [prev])
      expect(result.size).to eq(1)
      expect(result.first[:pattern_type]).to eq(:free_cf_turnaround)
    end

    it "既に黒字の場合は検出されない" do
      current = build_metric(free_cf_positive: true, free_cf: 500_000)
      prev = build_metric(
        id: 2,
        fiscal_year_end: Date.new(2024, 3, 31),
        free_cf_positive: true,
        free_cf: 300_000,
      )

      result = TrendTurningPoint.detect_free_cf_turnaround(current, [prev])
      expect(result).to be_empty
    end
  end

  describe ".detect_margin_bottom_reversal" do
    it "2期下落後の反転でmargin_bottom_reversalが検出される" do
      current = build_metric(operating_margin: BigDecimal("0.08"))
      prev = build_metric(
        id: 2,
        fiscal_year_end: Date.new(2024, 3, 31),
        operating_margin: BigDecimal("0.06"),
      )
      prev2 = build_metric(
        id: 3,
        fiscal_year_end: Date.new(2023, 3, 31),
        operating_margin: BigDecimal("0.10"),
      )

      result = TrendTurningPoint.detect_margin_bottom_reversal(current, [prev, prev2])
      expect(result.size).to eq(1)
      expect(result.first[:pattern_type]).to eq(:margin_bottom_reversal)
    end

    it "下落が続いている場合は検出されない" do
      current = build_metric(operating_margin: BigDecimal("0.05"))
      prev = build_metric(
        id: 2,
        fiscal_year_end: Date.new(2024, 3, 31),
        operating_margin: BigDecimal("0.08"),
      )
      prev2 = build_metric(
        id: 3,
        fiscal_year_end: Date.new(2023, 3, 31),
        operating_margin: BigDecimal("0.10"),
      )

      result = TrendTurningPoint.detect_margin_bottom_reversal(current, [prev, prev2])
      expect(result).to be_empty
    end

    it "データが2期分未満の場合は検出されない" do
      current = build_metric(operating_margin: BigDecimal("0.08"))
      prev = build_metric(
        id: 2,
        fiscal_year_end: Date.new(2024, 3, 31),
        operating_margin: BigDecimal("0.06"),
      )

      result = TrendTurningPoint.detect_margin_bottom_reversal(current, [prev])
      expect(result).to be_empty
    end
  end

  describe ".detect_roe_reversal" do
    it "ROEの底打ち反転が検出される" do
      current = build_metric(roe: BigDecimal("0.10"))
      prev = build_metric(
        id: 2,
        fiscal_year_end: Date.new(2024, 3, 31),
        roe: BigDecimal("0.07"),
      )
      prev2 = build_metric(
        id: 3,
        fiscal_year_end: Date.new(2023, 3, 31),
        roe: BigDecimal("0.12"),
      )

      result = TrendTurningPoint.detect_roe_reversal(current, [prev, prev2])
      expect(result.size).to eq(1)
      expect(result.first[:pattern_type]).to eq(:roe_reversal)
    end
  end

  describe ".detect_revenue_growth_acceleration" do
    it "売上成長の加速が検出される" do
      current = build_metric(revenue_yoy: BigDecimal("0.20"))
      prev = build_metric(
        id: 2,
        fiscal_year_end: Date.new(2024, 3, 31),
        revenue_yoy: BigDecimal("0.05"),
      )

      result = TrendTurningPoint.detect_revenue_growth_acceleration(current, [prev])
      expect(result.size).to eq(1)
      expect(result.first[:pattern_type]).to eq(:revenue_growth_acceleration)
      expect(result.first[:significance]).to eq(:high)
    end

    it "マイナス成長の場合は検出されない" do
      current = build_metric(revenue_yoy: BigDecimal("-0.05"))
      prev = build_metric(
        id: 2,
        fiscal_year_end: Date.new(2024, 3, 31),
        revenue_yoy: BigDecimal("-0.10"),
      )

      result = TrendTurningPoint.detect_revenue_growth_acceleration(current, [prev])
      expect(result).to be_empty
    end
  end

  describe ".detect_valuation_shift" do
    it "PERがセクター中央値の半分以下で検出される" do
      current = build_metric(data_json: { "per" => 5.0 })
      sector_stats = { "per" => { "median" => 15.0 } }

      result = TrendTurningPoint.detect_valuation_shift(current, sector_stats)
      expect(result.size).to eq(1)
      expect(result.first[:pattern_type]).to eq(:valuation_shift)
      expect(result.first[:data_json][:description]).to include("割安")
    end

    it "PERがセクター中央値の2倍以上で検出される" do
      current = build_metric(data_json: { "per" => 50.0 })
      sector_stats = { "per" => { "median" => 15.0 } }

      result = TrendTurningPoint.detect_valuation_shift(current, sector_stats)
      expect(result.size).to eq(1)
      expect(result.first[:data_json][:description]).to include("割高")
    end

    it "セクター統計がない場合は空配列を返す" do
      current = build_metric(data_json: { "per" => 15.0 })

      result = TrendTurningPoint.detect_valuation_shift(current, nil)
      expect(result).to be_empty
    end
  end

  describe ".detect_all" do
    it "複数パターンの転換点を同時検出する" do
      current = build_metric(
        consecutive_revenue_growth: 1,
        revenue_yoy: BigDecimal("0.15"),
        free_cf_positive: true,
        free_cf: 500_000,
        operating_margin: BigDecimal("0.10"),
        roe: BigDecimal("0.12"),
      )
      prev = build_metric(
        id: 2,
        fiscal_year_end: Date.new(2024, 3, 31),
        consecutive_revenue_growth: 0,
        revenue_yoy: BigDecimal("0.05"),
        free_cf_positive: false,
        free_cf: -100_000,
        operating_margin: BigDecimal("0.08"),
        roe: BigDecimal("0.10"),
      )
      prev2 = build_metric(
        id: 3,
        fiscal_year_end: Date.new(2023, 3, 31),
        consecutive_revenue_growth: 0,
        revenue_yoy: BigDecimal("-0.02"),
        free_cf_positive: false,
        free_cf: -200_000,
        operating_margin: BigDecimal("0.12"),
        roe: BigDecimal("0.14"),
      )

      result = TrendTurningPoint.detect_all(current, [prev, prev2])
      pattern_types = result.map { |r| r[:pattern_type] }

      expect(pattern_types).to include(:growth_resumption)
      expect(pattern_types).to include(:free_cf_turnaround)
      expect(pattern_types).to include(:revenue_growth_acceleration)
      expect(result.size).to be >= 3
    end

    it "空のmetric_historyではエラーにならない" do
      current = build_metric(consecutive_revenue_growth: 1)
      result = TrendTurningPoint.detect_all(current, [])
      expect(result).to be_empty
    end
  end

  describe ".get_consecutive_decline_count" do
    it "revenue_yoyのマイナス連続をカウントする" do
      metrics = [
        build_metric(id: 2, fiscal_year_end: Date.new(2024, 3, 31), revenue_yoy: BigDecimal("-0.05")),
        build_metric(id: 3, fiscal_year_end: Date.new(2023, 3, 31), revenue_yoy: BigDecimal("-0.03")),
        build_metric(id: 4, fiscal_year_end: Date.new(2022, 3, 31), revenue_yoy: BigDecimal("0.02")),
      ]

      count = TrendTurningPoint.get_consecutive_decline_count(metrics, :revenue_yoy)
      expect(count).to eq(2)
    end

    it "direction: :decreasingで値の減少をカウントする" do
      metrics = [
        build_metric(id: 2, fiscal_year_end: Date.new(2024, 3, 31), operating_margin: BigDecimal("0.06")),
        build_metric(id: 3, fiscal_year_end: Date.new(2023, 3, 31), operating_margin: BigDecimal("0.10")),
        build_metric(id: 4, fiscal_year_end: Date.new(2022, 3, 31), operating_margin: BigDecimal("0.12")),
      ]

      count = TrendTurningPoint.get_consecutive_decline_count(metrics, :operating_margin, direction: :decreasing)
      expect(count).to eq(2)
    end

    it "boolean_falseでfalse連続をカウントする" do
      metrics = [
        build_metric(id: 2, fiscal_year_end: Date.new(2024, 3, 31), free_cf_positive: false),
        build_metric(id: 3, fiscal_year_end: Date.new(2023, 3, 31), free_cf_positive: false),
        build_metric(id: 4, fiscal_year_end: Date.new(2022, 3, 31), free_cf_positive: true),
      ]

      count = TrendTurningPoint.get_consecutive_decline_count(metrics, :free_cf_positive, boolean_false: true)
      expect(count).to eq(2)
    end
  end
end
