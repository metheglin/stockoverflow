require "rails_helper"

RSpec.describe ScreeningPreset::MultiPeriodConditionEvaluator do
  let!(:company_a) do
    Company.create!(
      name: "Stable ROE Corp",
      securities_code: "10010",
      edinet_code: "E00001",
      sector_33_code: "3050",
      market_code: "111",
      listed: true
    )
  end

  let!(:company_b) do
    Company.create!(
      name: "Improving Margin Corp",
      securities_code: "20020",
      edinet_code: "E00002",
      sector_33_code: "3100",
      market_code: "111",
      listed: true
    )
  end

  let!(:company_c) do
    Company.create!(
      name: "FCF Turnaround Corp",
      securities_code: "30030",
      edinet_code: "E00003",
      sector_33_code: "5050",
      market_code: "112",
      listed: true
    )
  end

  # Company A: ROE consistently > 10% for 5 years
  # Years: 2021-2025, ROE = 0.12, 0.11, 0.13, 0.10, 0.14
  # operating_margin: last 3 years consecutively improving (0.13, 0.15, 0.17)
  let!(:metrics_a) do
    [
      { fiscal_year_end: "2021-03-31", roe: 0.12, operating_margin: 0.15, revenue_yoy: 0.10, operating_cf_positive: true, free_cf_positive: true },
      { fiscal_year_end: "2022-03-31", roe: 0.11, operating_margin: 0.14, revenue_yoy: 0.08, operating_cf_positive: true, free_cf_positive: true },
      { fiscal_year_end: "2023-03-31", roe: 0.13, operating_margin: 0.13, revenue_yoy: 0.12, operating_cf_positive: true, free_cf_positive: true },
      { fiscal_year_end: "2024-03-31", roe: 0.10, operating_margin: 0.15, revenue_yoy: 0.05, operating_cf_positive: true, free_cf_positive: true },
      { fiscal_year_end: "2025-03-31", roe: 0.14, operating_margin: 0.17, revenue_yoy: 0.15, operating_cf_positive: true, free_cf_positive: true },
    ].map do |attrs|
      fv = FinancialValue.create!(
        company: company_a,
        fiscal_year_end: attrs[:fiscal_year_end],
        scope: :consolidated,
        period_type: :annual,
        net_sales: 100_000_000
      )
      FinancialMetric.create!(
        company: company_a,
        financial_value: fv,
        fiscal_year_end: attrs[:fiscal_year_end],
        scope: :consolidated,
        period_type: :annual,
        roe: attrs[:roe],
        operating_margin: attrs[:operating_margin],
        revenue_yoy: attrs[:revenue_yoy],
        operating_cf_positive: attrs[:operating_cf_positive],
        free_cf_positive: attrs[:free_cf_positive]
      )
    end
  end

  # Company B: Operating margin improving 3 years (2023 < 2024 < 2025)
  # ROE only > 10% in 3 of 5 years
  let!(:metrics_b) do
    [
      { fiscal_year_end: "2021-03-31", roe: 0.08, operating_margin: 0.10, revenue_yoy: 0.05, operating_cf_positive: true, free_cf_positive: false },
      { fiscal_year_end: "2022-03-31", roe: 0.12, operating_margin: 0.09, revenue_yoy: 0.06, operating_cf_positive: true, free_cf_positive: false },
      { fiscal_year_end: "2023-03-31", roe: 0.11, operating_margin: 0.11, revenue_yoy: 0.07, operating_cf_positive: true, free_cf_positive: false },
      { fiscal_year_end: "2024-03-31", roe: 0.07, operating_margin: 0.13, revenue_yoy: 0.09, operating_cf_positive: true, free_cf_positive: false },
      { fiscal_year_end: "2025-03-31", roe: 0.09, operating_margin: 0.15, revenue_yoy: 0.11, operating_cf_positive: true, free_cf_positive: true },
    ].map do |attrs|
      fv = FinancialValue.create!(
        company: company_b,
        fiscal_year_end: attrs[:fiscal_year_end],
        scope: :consolidated,
        period_type: :annual,
        net_sales: 50_000_000
      )
      FinancialMetric.create!(
        company: company_b,
        financial_value: fv,
        fiscal_year_end: attrs[:fiscal_year_end],
        scope: :consolidated,
        period_type: :annual,
        roe: attrs[:roe],
        operating_margin: attrs[:operating_margin],
        revenue_yoy: attrs[:revenue_yoy],
        operating_cf_positive: attrs[:operating_cf_positive],
        free_cf_positive: attrs[:free_cf_positive]
      )
    end
  end

  # Company C: FCF transitioned from negative to positive (2024: false -> 2025: true)
  # Only 2 years of data
  let!(:metrics_c) do
    [
      { fiscal_year_end: "2024-03-31", roe: 0.03, operating_margin: 0.05, revenue_yoy: 0.20, operating_cf_positive: false, free_cf_positive: false },
      { fiscal_year_end: "2025-03-31", roe: 0.05, operating_margin: 0.07, revenue_yoy: 0.25, operating_cf_positive: true, free_cf_positive: true },
    ].map do |attrs|
      fv = FinancialValue.create!(
        company: company_c,
        fiscal_year_end: attrs[:fiscal_year_end],
        scope: :consolidated,
        period_type: :annual,
        net_sales: 10_000_000
      )
      FinancialMetric.create!(
        company: company_c,
        financial_value: fv,
        fiscal_year_end: attrs[:fiscal_year_end],
        scope: :consolidated,
        period_type: :annual,
        roe: attrs[:roe],
        operating_margin: attrs[:operating_margin],
        revenue_yoy: attrs[:revenue_yoy],
        operating_cf_positive: attrs[:operating_cf_positive],
        free_cf_positive: attrs[:free_cf_positive]
      )
    end
  end

  describe "#evaluate_temporal_condition" do
    let(:all_company_ids) { [company_a.id, company_b.id, company_c.id] }

    def build_evaluator(conditions)
      described_class.new(
        company_ids: all_company_ids,
        conditions: conditions
      )
    end

    def load_history(company)
      FinancialMetric
        .where(company_id: company.id, scope: :consolidated, period_type: :annual)
        .order(:fiscal_year_end)
        .to_a
    end

    context "at_least_n_of_m" do
      it "5期中4期ROE > 10%を達成する企業が条件を満たす" do
        condition = {
          temporal_type: "at_least_n_of_m",
          field: "roe",
          threshold: 0.10,
          comparison: "gte",
          n: 4,
          m: 5
        }
        evaluator = build_evaluator([condition])
        history = load_history(company_a)

        # Company A: ROE = 0.12, 0.11, 0.13, 0.10, 0.14 => 5/5 >= 0.10
        expect(evaluator.evaluate_temporal_condition(history, condition.deep_symbolize_keys)).to be true
      end

      it "5期中3期しか達成しない企業が条件を満たさない" do
        condition = {
          temporal_type: "at_least_n_of_m",
          field: "roe",
          threshold: 0.10,
          comparison: "gte",
          n: 4,
          m: 5
        }
        evaluator = build_evaluator([condition])
        history = load_history(company_b)

        # Company B: ROE = 0.08, 0.12, 0.11, 0.07, 0.09 => 2/5 >= 0.10
        expect(evaluator.evaluate_temporal_condition(history, condition.deep_symbolize_keys)).to be false
      end

      it "履歴データが不足する場合にfalseとする" do
        condition = {
          temporal_type: "at_least_n_of_m",
          field: "roe",
          threshold: 0.10,
          comparison: "gte",
          n: 4,
          m: 5
        }
        evaluator = build_evaluator([condition])
        history = load_history(company_c) # only 2 years

        expect(evaluator.evaluate_temporal_condition(history, condition.deep_symbolize_keys)).to be false
      end
    end

    context "consecutive (improving)" do
      it "3期連続改善の企業が条件を満たす" do
        condition = {
          temporal_type: "consecutive",
          field: "operating_margin",
          direction: "improving",
          n: 3
        }
        evaluator = build_evaluator([condition])
        history = load_history(company_b)

        # Company B operating_margin: 0.10, 0.09, 0.11, 0.13, 0.15
        # Last 4 values (3 transitions): 0.09 -> 0.11 -> 0.13 -> 0.15 (all improving)
        expect(evaluator.evaluate_temporal_condition(history, condition.deep_symbolize_keys)).to be true
      end

      it "途中で悪化がある企業が条件を満たさない" do
        condition = {
          temporal_type: "consecutive",
          field: "operating_margin",
          direction: "improving",
          n: 4
        }
        evaluator = build_evaluator([condition])
        history = load_history(company_b)

        # Company B operating_margin: 0.10, 0.09, 0.11, 0.13, 0.15
        # Last 5 values (4 transitions): 0.10 -> 0.09 (decrease!) -> 0.11 -> 0.13 -> 0.15
        expect(evaluator.evaluate_temporal_condition(history, condition.deep_symbolize_keys)).to be false
      end
    end

    context "improving" do
      it "直近N期分でフィールド値が全て前期より上昇している場合にtrueを返す" do
        condition = {
          temporal_type: "improving",
          field: "revenue_yoy",
          n: 3
        }
        evaluator = build_evaluator([condition])
        history = load_history(company_b)

        # Company B revenue_yoy: 0.05, 0.06, 0.07, 0.09, 0.11
        # Last 4 values (3 transitions): 0.06 -> 0.07 -> 0.09 -> 0.11 (all improving)
        expect(evaluator.evaluate_temporal_condition(history, condition.deep_symbolize_keys)).to be true
      end
    end

    context "deteriorating" do
      it "直近N期分でフィールド値が全て前期より下降している場合にtrueを返す" do
        condition = {
          temporal_type: "deteriorating",
          field: "roe",
          n: 2
        }
        evaluator = build_evaluator([condition])
        history = load_history(company_b)

        # Company B ROE: 0.08, 0.12, 0.11, 0.07, 0.09
        # Last 3 values (2 transitions): 0.11 -> 0.07 -> 0.09 (second is up, not deteriorating)
        expect(evaluator.evaluate_temporal_condition(history, condition.deep_symbolize_keys)).to be false
      end
    end

    context "transition_positive" do
      it "前期false→当期trueで条件を満たす" do
        condition = {
          temporal_type: "transition_positive",
          field: "free_cf_positive"
        }
        evaluator = build_evaluator([condition])
        history = load_history(company_c)

        # Company C free_cf_positive: false -> true
        expect(evaluator.evaluate_temporal_condition(history, condition.deep_symbolize_keys)).to be true
      end

      it "前期もtrueの場合は条件を満たさない" do
        condition = {
          temporal_type: "transition_positive",
          field: "free_cf_positive"
        }
        evaluator = build_evaluator([condition])
        history = load_history(company_a)

        # Company A free_cf_positive: all true
        expect(evaluator.evaluate_temporal_condition(history, condition.deep_symbolize_keys)).to be false
      end

      it "前期false→当期trueで別のbooleanフィールドでも動作する" do
        condition = {
          temporal_type: "transition_positive",
          field: "operating_cf_positive"
        }
        evaluator = build_evaluator([condition])
        history = load_history(company_c)

        # Company C operating_cf_positive: false -> true
        expect(evaluator.evaluate_temporal_condition(history, condition.deep_symbolize_keys)).to be true
      end
    end

    context "transition_negative" do
      it "前期true→当期falseで条件を満たす" do
        condition = {
          temporal_type: "transition_negative",
          field: "free_cf_positive"
        }
        evaluator = build_evaluator([condition])

        # Company Bの2024→2025はfalse→trueなので満たさない
        # 逆パターンのデータを使ってテスト: Company A は常にtrue
        history_b = load_history(company_b)
        # Company B free_cf_positive: false, false, false, false, true → 前期false,当期true → 満たさない
        expect(evaluator.evaluate_temporal_condition(history_b, condition.deep_symbolize_keys)).to be false
      end
    end

    context "invalid conditions" do
      it "不正なtemporal_typeの場合はfalseを返す" do
        condition = {
          temporal_type: "invalid_type",
          field: "roe",
          n: 3
        }
        evaluator = build_evaluator([condition])
        history = load_history(company_a)

        expect(evaluator.evaluate_temporal_condition(history, condition.deep_symbolize_keys)).to be false
      end

      it "不正なフィールドの場合はfalseを返す" do
        condition = {
          temporal_type: "at_least_n_of_m",
          field: "invalid_field",
          threshold: 0.10,
          comparison: "gte",
          n: 3,
          m: 5
        }
        evaluator = build_evaluator([condition])
        history = load_history(company_a)

        expect(evaluator.evaluate_temporal_condition(history, condition.deep_symbolize_keys)).to be false
      end
    end
  end

  describe "#execute" do
    it "複数のtemporal条件が全てAND条件で適用される" do
      conditions = [
        {
          temporal_type: "at_least_n_of_m",
          field: "roe",
          threshold: 0.10,
          comparison: "gte",
          n: 4,
          m: 5
        },
        {
          temporal_type: "consecutive",
          field: "operating_margin",
          direction: "improving",
          n: 2
        }
      ]

      evaluator = described_class.new(
        company_ids: [company_a.id, company_b.id, company_c.id],
        conditions: conditions
      )

      result = evaluator.execute

      # Company A: ROE 5/5 >= 0.10 (pass), margin 0.13->0.17 (2 consecutive improving, pass) => pass
      # Company B: ROE 2/5 (fail) => fail
      # Company C: insufficient data => fail
      expect(result).to contain_exactly(company_a.id)
    end

    it "空のcompany_idsに対して空配列を返す" do
      evaluator = described_class.new(
        company_ids: [],
        conditions: [
          { temporal_type: "at_least_n_of_m", field: "roe", threshold: 0.10, n: 3, m: 5 }
        ]
      )

      expect(evaluator.execute).to eq([])
    end

    it "空のconditionsに対して空配列を返す" do
      evaluator = described_class.new(
        company_ids: [company_a.id],
        conditions: []
      )

      expect(evaluator.execute).to eq([])
    end

    it "transition_positiveで正しい企業のみ返す" do
      evaluator = described_class.new(
        company_ids: [company_a.id, company_b.id, company_c.id],
        conditions: [
          { temporal_type: "transition_positive", field: "free_cf_positive" }
        ]
      )

      result = evaluator.execute

      # Company B: false -> true (last 2), Company C: false -> true
      expect(result).to contain_exactly(company_b.id, company_c.id)
    end
  end
end
