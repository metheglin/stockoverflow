require "rails_helper"

RSpec.describe FinancialEvent do
  describe ".detect_events" do
    it "前期データがない場合にエラーにならない" do
      metric = FinancialMetric.new(
        id: 1,
        company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        consecutive_revenue_growth: 1,
        revenue_yoy: BigDecimal("0.1"),
      )

      events = FinancialEvent.detect_events(metric, nil)
      expect(events).to be_an(Array)
      # streak_started (0→1) + no errors
      expect(events.select { |e| e[:event_type] == :streak_started }).not_to be_empty
    end
  end

  describe ".detect_streak_events" do
    it "連続増収が0→1でstreak_startedが検出される" do
      current = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        consecutive_revenue_growth: 1,
      )
      previous = FinancialMetric.new(
        id: 2, company_id: 1,
        fiscal_year_end: Date.new(2024, 3, 31),
        consecutive_revenue_growth: 0,
      )

      events = FinancialEvent.detect_streak_events(current, previous)
      started = events.find { |e| e[:event_type] == :streak_started }
      expect(started).not_to be_nil
      expect(started[:severity]).to eq(:info)
    end

    it "3期以上のストリーク中断でstreak_brokenがcriticalで検出される" do
      current = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        consecutive_revenue_growth: 0,
      )
      previous = FinancialMetric.new(
        id: 2, company_id: 1,
        fiscal_year_end: Date.new(2024, 3, 31),
        consecutive_revenue_growth: 5,
      )

      events = FinancialEvent.detect_streak_events(current, previous)
      broken = events.find { |e| e[:event_type] == :streak_broken }
      expect(broken).not_to be_nil
      expect(broken[:severity]).to eq(:critical)
      expect(broken[:data_json][:previous_value]).to eq(5)
    end

    it "1期のストリーク中断ではnotableで検出される" do
      current = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        consecutive_revenue_growth: 0,
      )
      previous = FinancialMetric.new(
        id: 2, company_id: 1,
        fiscal_year_end: Date.new(2024, 3, 31),
        consecutive_revenue_growth: 1,
      )

      events = FinancialEvent.detect_streak_events(current, previous)
      broken = events.find { |e| e[:event_type] == :streak_broken }
      expect(broken).not_to be_nil
      expect(broken[:severity]).to eq(:notable)
    end

    it "streak_milestoneが3期で検出される" do
      current = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        consecutive_revenue_growth: 3,
      )
      previous = FinancialMetric.new(
        id: 2, company_id: 1,
        fiscal_year_end: Date.new(2024, 3, 31),
        consecutive_revenue_growth: 2,
      )

      events = FinancialEvent.detect_streak_events(current, previous)
      milestone = events.find { |e| e[:event_type] == :streak_milestone }
      expect(milestone).not_to be_nil
      expect(milestone[:severity]).to eq(:notable)
      expect(milestone[:data_json][:streak_count]).to eq(3)
    end

    it "streak_milestoneが5期でcriticalになる" do
      current = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        consecutive_revenue_growth: 5,
      )
      previous = FinancialMetric.new(
        id: 2, company_id: 1,
        fiscal_year_end: Date.new(2024, 3, 31),
        consecutive_revenue_growth: 4,
      )

      events = FinancialEvent.detect_streak_events(current, previous)
      milestone = events.find { |e| e[:event_type] == :streak_milestone }
      expect(milestone).not_to be_nil
      expect(milestone[:severity]).to eq(:critical)
    end
  end

  describe ".detect_fcf_events" do
    it "FCFの正転換イベントが正しく検出される" do
      current = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        free_cf: 500_000, free_cf_positive: true,
      )
      previous = FinancialMetric.new(
        id: 2, company_id: 1,
        fiscal_year_end: Date.new(2024, 3, 31),
        free_cf: -200_000, free_cf_positive: false,
      )

      events = FinancialEvent.detect_fcf_events(current, previous)
      positive = events.find { |e| e[:event_type] == :fcf_turned_positive }
      expect(positive).not_to be_nil
      expect(positive[:severity]).to eq(:notable)
    end

    it "FCFの負転換イベントが正しく検出される" do
      current = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        free_cf: -100_000, free_cf_positive: false,
      )
      previous = FinancialMetric.new(
        id: 2, company_id: 1,
        fiscal_year_end: Date.new(2024, 3, 31),
        free_cf: 300_000, free_cf_positive: true,
      )

      events = FinancialEvent.detect_fcf_events(current, previous)
      negative = events.find { |e| e[:event_type] == :fcf_turned_negative }
      expect(negative).not_to be_nil
      expect(negative[:severity]).to eq(:notable)
    end

    it "FCFデータがない場合は空配列を返す" do
      current = FinancialMetric.new(id: 1, company_id: 1, fiscal_year_end: Date.new(2025, 3, 31))
      previous = FinancialMetric.new(id: 2, company_id: 1, fiscal_year_end: Date.new(2024, 3, 31))

      events = FinancialEvent.detect_fcf_events(current, previous)
      expect(events).to be_empty
    end
  end

  describe ".detect_margin_events" do
    it "営業利益率の大幅改善でmargin_expansionが検出される" do
      current = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        operating_margin: BigDecimal("0.18"),
      )
      previous = FinancialMetric.new(
        id: 2, company_id: 1,
        fiscal_year_end: Date.new(2024, 3, 31),
        operating_margin: BigDecimal("0.10"),
      )

      events = FinancialEvent.detect_margin_events(current, previous)
      expansion = events.find { |e| e[:event_type] == :margin_expansion }
      expect(expansion).not_to be_nil
      expect(expansion[:severity]).to eq(:critical)
    end

    it "営業利益率の大幅悪化でmargin_contractionが検出される" do
      current = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        operating_margin: BigDecimal("0.05"),
      )
      previous = FinancialMetric.new(
        id: 2, company_id: 1,
        fiscal_year_end: Date.new(2024, 3, 31),
        operating_margin: BigDecimal("0.12"),
      )

      events = FinancialEvent.detect_margin_events(current, previous)
      contraction = events.find { |e| e[:event_type] == :margin_contraction }
      expect(contraction).not_to be_nil
      expect(contraction[:severity]).to eq(:critical)
    end
  end

  describe ".detect_roe_events" do
    it "ROEが15%を超過した場合にroe_crossed_thresholdが検出される" do
      current = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        roe: BigDecimal("0.16"),
      )
      previous = FinancialMetric.new(
        id: 2, company_id: 1,
        fiscal_year_end: Date.new(2024, 3, 31),
        roe: BigDecimal("0.12"),
      )

      events = FinancialEvent.detect_roe_events(current, previous)
      crossed = events.find { |e| e[:event_type] == :roe_crossed_threshold }
      expect(crossed).not_to be_nil
      expect(crossed[:severity]).to eq(:notable)
    end

    it "既に閾値以上の場合はイベントが発生しない" do
      current = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        roe: BigDecimal("0.18"),
      )
      previous = FinancialMetric.new(
        id: 2, company_id: 1,
        fiscal_year_end: Date.new(2024, 3, 31),
        roe: BigDecimal("0.16"),
      )

      events = FinancialEvent.detect_roe_events(current, previous)
      expect(events).to be_empty
    end
  end

  describe ".detect_extreme_growth_events" do
    it "売上50%以上成長でextreme_growthが検出される" do
      metric = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        revenue_yoy: BigDecimal("0.6"),
      )

      events = FinancialEvent.detect_extreme_growth_events(metric)
      growth = events.find { |e| e[:event_type] == :extreme_growth }
      expect(growth).not_to be_nil
      expect(growth[:severity]).to eq(:critical)
    end

    it "売上30%以上減少でextreme_declineが検出される" do
      metric = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        revenue_yoy: BigDecimal("-0.35"),
      )

      events = FinancialEvent.detect_extreme_growth_events(metric)
      decline = events.find { |e| e[:event_type] == :extreme_decline }
      expect(decline).not_to be_nil
      expect(decline[:severity]).to eq(:critical)
    end
  end

  describe ".detect_acceleration_events" do
    it "減速→加速転換でgrowth_accelerationが検出される" do
      current = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        data_json: { "revenue_growth_acceleration" => 0.05 },
      )
      previous = FinancialMetric.new(
        id: 2, company_id: 1,
        fiscal_year_end: Date.new(2024, 3, 31),
        data_json: { "revenue_growth_acceleration" => -0.03 },
      )

      events = FinancialEvent.detect_acceleration_events(current, previous)
      accel = events.find { |e| e[:event_type] == :growth_acceleration }
      expect(accel).not_to be_nil
      expect(accel[:severity]).to eq(:notable)
    end

    it "加速→減速転換でgrowth_decelerationが検出される" do
      current = FinancialMetric.new(
        id: 1, company_id: 1,
        fiscal_year_end: Date.new(2025, 3, 31),
        data_json: { "revenue_growth_acceleration" => -0.05 },
      )
      previous = FinancialMetric.new(
        id: 2, company_id: 1,
        fiscal_year_end: Date.new(2024, 3, 31),
        data_json: { "revenue_growth_acceleration" => 0.03 },
      )

      events = FinancialEvent.detect_acceleration_events(current, previous)
      decel = events.find { |e| e[:event_type] == :growth_deceleration }
      expect(decel).not_to be_nil
      expect(decel[:severity]).to eq(:info)
    end
  end
end
