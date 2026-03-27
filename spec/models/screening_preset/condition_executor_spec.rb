require "rails_helper"

RSpec.describe ScreeningPreset::ConditionExecutor do
  let!(:company_a) do
    Company.create!(
      name: "Company A",
      securities_code: "10010",
      edinet_code: "E00001",
      sector_33_code: "3050",
      sector_17_code: "1",
      market_code: "111",
      scale_category: "TOPIX Large70",
      listed: true
    )
  end

  let!(:company_b) do
    Company.create!(
      name: "Company B",
      securities_code: "20020",
      edinet_code: "E00002",
      sector_33_code: "3100",
      sector_17_code: "2",
      market_code: "111",
      scale_category: "TOPIX Mid400",
      listed: true
    )
  end

  let!(:company_c) do
    Company.create!(
      name: "Company C",
      securities_code: "30030",
      edinet_code: "E00003",
      sector_33_code: "5050",
      sector_17_code: "5",
      market_code: "112",
      scale_category: "TOPIX Small1",
      listed: true
    )
  end

  let!(:unlisted_company) do
    Company.create!(
      name: "Unlisted Co",
      securities_code: "90090",
      edinet_code: "E00009",
      sector_33_code: "3050",
      market_code: "111",
      listed: false
    )
  end

  let!(:fv_a) do
    FinancialValue.create!(
      company: company_a,
      fiscal_year_end: "2025-03-31",
      scope: :consolidated,
      period_type: :annual,
      net_sales: 100_000_000,
      operating_income: 15_000_000,
      net_income: 10_000_000,
      total_assets: 200_000_000,
      net_assets: 80_000_000,
      operating_cf: 20_000_000,
      investing_cf: -10_000_000
    )
  end

  let!(:metric_a) do
    FinancialMetric.create!(
      company: company_a,
      financial_value: fv_a,
      fiscal_year_end: "2025-03-31",
      scope: :consolidated,
      period_type: :annual,
      revenue_yoy: 0.15,
      operating_income_yoy: 0.20,
      ordinary_income_yoy: 0.18,
      net_income_yoy: 0.12,
      eps_yoy: 0.10,
      roe: 0.125,
      roa: 0.05,
      operating_margin: 0.15,
      ordinary_margin: 0.16,
      net_margin: 0.10,
      free_cf: 10_000_000,
      operating_cf_positive: true,
      investing_cf_negative: true,
      free_cf_positive: true,
      consecutive_revenue_growth: 6,
      consecutive_profit_growth: 6,
      data_json: {
        "per" => 15.0,
        "pbr" => 1.2,
        "psr" => 1.5,
        "dividend_yield" => 0.025,
        "composite_score" => 0.85,
        "growth_score" => 0.80,
        "quality_score" => 0.75,
        "value_score" => 0.90,
      }
    )
  end

  let!(:fv_b) do
    FinancialValue.create!(
      company: company_b,
      fiscal_year_end: "2025-03-31",
      scope: :consolidated,
      period_type: :annual,
      net_sales: 50_000_000,
      operating_income: 5_000_000,
      net_income: 3_000_000,
      total_assets: 100_000_000,
      net_assets: 40_000_000,
      operating_cf: 8_000_000,
      investing_cf: -12_000_000
    )
  end

  let!(:metric_b) do
    FinancialMetric.create!(
      company: company_b,
      financial_value: fv_b,
      fiscal_year_end: "2025-03-31",
      scope: :consolidated,
      period_type: :annual,
      revenue_yoy: 0.08,
      operating_income_yoy: 0.05,
      ordinary_income_yoy: 0.04,
      net_income_yoy: 0.03,
      eps_yoy: 0.02,
      roe: 0.075,
      roa: 0.03,
      operating_margin: 0.10,
      ordinary_margin: 0.09,
      net_margin: 0.06,
      free_cf: -4_000_000,
      operating_cf_positive: true,
      investing_cf_negative: true,
      free_cf_positive: false,
      consecutive_revenue_growth: 3,
      consecutive_profit_growth: 2,
      data_json: {
        "per" => 20.0,
        "pbr" => 0.8,
        "psr" => 0.5,
        "dividend_yield" => 0.04,
        "composite_score" => 0.60,
        "growth_score" => 0.50,
        "quality_score" => 0.65,
        "value_score" => 0.70,
      }
    )
  end

  let!(:fv_c) do
    FinancialValue.create!(
      company: company_c,
      fiscal_year_end: "2025-03-31",
      scope: :consolidated,
      period_type: :annual,
      net_sales: 10_000_000,
      operating_income: 500_000,
      net_income: 200_000,
      total_assets: 30_000_000,
      net_assets: 10_000_000,
      operating_cf: -1_000_000,
      investing_cf: -500_000
    )
  end

  let!(:metric_c) do
    FinancialMetric.create!(
      company: company_c,
      financial_value: fv_c,
      fiscal_year_end: "2025-03-31",
      scope: :consolidated,
      period_type: :annual,
      revenue_yoy: 0.25,
      operating_income_yoy: 0.30,
      ordinary_income_yoy: 0.28,
      net_income_yoy: 0.35,
      eps_yoy: 0.32,
      roe: 0.02,
      roa: 0.007,
      operating_margin: 0.05,
      ordinary_margin: 0.04,
      net_margin: 0.02,
      free_cf: -1_500_000,
      operating_cf_positive: false,
      investing_cf_negative: true,
      free_cf_positive: false,
      consecutive_revenue_growth: 8,
      consecutive_profit_growth: 7,
      data_json: {
        "per" => 50.0,
        "pbr" => 3.0,
        "psr" => 5.0,
        "dividend_yield" => 0.005,
        "composite_score" => 0.40,
        "growth_score" => 0.90,
        "quality_score" => 0.30,
        "value_score" => 0.20,
      }
    )
  end

  # 非上場企業のメトリクス（検索結果に含まれないことの確認用）
  let!(:fv_unlisted) do
    FinancialValue.create!(
      company: unlisted_company,
      fiscal_year_end: "2025-03-31",
      scope: :consolidated,
      period_type: :annual,
      net_sales: 5_000_000,
      operating_income: 500_000,
      net_income: 300_000,
      total_assets: 20_000_000,
      net_assets: 8_000_000
    )
  end

  let!(:metric_unlisted) do
    FinancialMetric.create!(
      company: unlisted_company,
      financial_value: fv_unlisted,
      fiscal_year_end: "2025-03-31",
      scope: :consolidated,
      period_type: :annual,
      revenue_yoy: 0.50,
      roe: 0.20,
      operating_cf_positive: true,
      consecutive_revenue_growth: 10,
      consecutive_profit_growth: 10,
      data_json: { "composite_score" => 0.99 }
    )
  end

  describe "#build_base_scope" do
    it "scope_typeとperiod_typeが正しく適用される" do
      executor = described_class.new(
        conditions_json: { scope_type: "consolidated", period_type: "annual" }
      )
      scope = executor.build_base_scope

      expect(scope.to_a).to contain_exactly(metric_a, metric_b, metric_c)
    end

    it "非上場企業が除外される" do
      executor = described_class.new(
        conditions_json: { scope_type: "consolidated", period_type: "annual" }
      )
      scope = executor.build_base_scope
      company_ids = scope.pluck(:company_id)

      expect(company_ids).not_to include(unlisted_company.id)
    end

    it "最新期間のみが取得される" do
      # company_aに古い期間のメトリクスを追加
      old_fv = FinancialValue.create!(
        company: company_a,
        fiscal_year_end: "2024-03-31",
        scope: :consolidated,
        period_type: :annual,
        net_sales: 90_000_000
      )
      FinancialMetric.create!(
        company: company_a,
        financial_value: old_fv,
        fiscal_year_end: "2024-03-31",
        scope: :consolidated,
        period_type: :annual,
        revenue_yoy: 0.10
      )

      executor = described_class.new(
        conditions_json: { scope_type: "consolidated", period_type: "annual" }
      )
      scope = executor.build_base_scope
      a_metrics = scope.where(company_id: company_a.id).to_a

      expect(a_metrics.size).to eq(1)
      expect(a_metrics.first.fiscal_year_end.to_s).to eq("2025-03-31")
    end
  end

  describe "#apply_conditions" do
    context "metric_range条件" do
      it "min条件で正しくフィルタされる" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_range", field: "roe", min: 0.10 }
            ]
          }
        )
        results = executor.execute

        expect(results.map { |r| r[:company] }).to contain_exactly(company_a)
      end

      it "min/max両方の条件で正しくフィルタされる" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_range", field: "revenue_yoy", min: 0.05, max: 0.20 }
            ]
          }
        )
        results = executor.execute

        expect(results.map { |r| r[:company] }).to contain_exactly(company_a, company_b)
      end

      it "連続増収の条件でフィルタされる" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_range", field: "consecutive_revenue_growth", min: 6 }
            ]
          }
        )
        results = executor.execute

        expect(results.map { |r| r[:company] }).to contain_exactly(company_a, company_c)
      end
    end

    context "metric_boolean条件" do
      it "boolean条件で正しくフィルタされる" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_boolean", field: "operating_cf_positive", value: true },
              { type: "metric_boolean", field: "free_cf_positive", value: true },
            ]
          }
        )
        results = executor.execute

        expect(results.map { |r| r[:company] }).to contain_exactly(company_a)
      end

      it "false値でフィルタされる" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_boolean", field: "free_cf_positive", value: false }
            ]
          }
        )
        results = executor.execute

        expect(results.map { |r| r[:company] }).to contain_exactly(company_b, company_c)
      end
    end

    context "company_attribute条件" do
      it "セクターコードで企業をフィルタする" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "company_attribute", field: "sector_33_code", values: ["3050", "3100"] }
            ]
          }
        )
        results = executor.execute

        expect(results.map { |r| r[:company] }).to contain_exactly(company_a, company_b)
      end

      it "market_codeでフィルタする" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "company_attribute", field: "market_code", values: ["112"] }
            ]
          }
        )
        results = executor.execute

        expect(results.map { |r| r[:company] }).to contain_exactly(company_c)
      end
    end

    context "AND/OR論理演算" do
      it "AND条件が正しく動作する" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_range", field: "roe", min: 0.05 },
              { type: "metric_boolean", field: "operating_cf_positive", value: true },
            ]
          }
        )
        results = executor.execute

        expect(results.map { |r| r[:company] }).to contain_exactly(company_a, company_b)
      end

      it "OR条件が正しく動作する" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "or",
            conditions: [
              { type: "metric_range", field: "roe", min: 0.10 },
              { type: "metric_range", field: "revenue_yoy", min: 0.20 },
            ]
          }
        )
        results = executor.execute

        companies = results.map { |r| r[:company] }
        expect(companies).to contain_exactly(company_a, company_c)
      end

      it "ネストされたAND/OR条件が正しく動作する" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_boolean", field: "investing_cf_negative", value: true },
              {
                logic: "or",
                conditions: [
                  { type: "metric_range", field: "roe", min: 0.10 },
                  { type: "metric_range", field: "revenue_yoy", min: 0.20 },
                ]
              }
            ]
          }
        )
        results = executor.execute

        companies = results.map { |r| r[:company] }
        expect(companies).to contain_exactly(company_a, company_c)
      end
    end
  end

  describe "#execute" do
    context "data_json_rangeポストフィルタ" do
      it "data_json内のフィールドで範囲フィルタが機能する" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "data_json_range", field: "pbr", max: 1.5 }
            ]
          }
        )
        results = executor.execute

        expect(results.map { |r| r[:company] }).to contain_exactly(company_a, company_b)
      end

      it "min/max両方でdata_jsonフィルタが機能する" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "data_json_range", field: "per", min: 10.0, max: 25.0 }
            ]
          }
        )
        results = executor.execute

        expect(results.map { |r| r[:company] }).to contain_exactly(company_a, company_b)
      end

      it "composite_scoreでフィルタが機能する" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "data_json_range", field: "composite_score", min: 0.50 }
            ]
          }
        )
        results = executor.execute

        expect(results.map { |r| r[:company] }).to contain_exactly(company_a, company_b)
      end
    end

    context "metric_top_n" do
      it "上位N件に正しく制限される（desc）" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_top_n", field: "roe", direction: "desc", n: 2 }
            ]
          }
        )
        results = executor.execute

        expect(results.size).to eq(2)
        expect(results.map { |r| r[:company] }).to contain_exactly(company_a, company_b)
      end

      it "上位N件に正しく制限される（asc）" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_top_n", field: "per", direction: "asc", n: 1 }
            ]
          }
        )
        results = executor.execute

        expect(results.size).to eq(1)
        expect(results.first[:company]).to eq(company_a)
      end

      it "data_jsonフィールドでもtop_nが動作する" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_top_n", field: "composite_score", direction: "desc", n: 2 }
            ]
          }
        )
        results = executor.execute

        expect(results.size).to eq(2)
        companies = results.map { |r| r[:company] }
        expect(companies).to contain_exactly(company_a, company_b)
      end
    end

    context "preset_ref" do
      it "参照先プリセットの結果との積集合でフィルタされる" do
        ref_preset = ScreeningPreset.create!(
          name: "高ROEプリセット",
          preset_type: :builtin,
          status: :enabled,
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_range", field: "roe", min: 0.10 }
            ]
          },
          display_json: {}
        )

        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_range", field: "consecutive_revenue_growth", min: 6 },
              { type: "preset_ref", preset_id: ref_preset.id },
            ]
          }
        )
        results = executor.execute

        expect(results.map { |r| r[:company] }).to contain_exactly(company_a)
      end

      it "循環参照で例外が発生しない（深さ制限テスト）" do
        preset_1 = ScreeningPreset.create!(
          name: "Preset 1",
          preset_type: :custom,
          status: :enabled,
          conditions_json: { scope_type: "consolidated", period_type: "annual", logic: "and", conditions: [] },
          display_json: {}
        )

        preset_2 = ScreeningPreset.create!(
          name: "Preset 2",
          preset_type: :custom,
          status: :enabled,
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [{ type: "preset_ref", preset_id: preset_1.id }]
          },
          display_json: {}
        )

        # preset_1をpreset_2を参照するよう循環的に更新
        preset_1.update!(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [{ type: "preset_ref", preset_id: preset_2.id }]
          }
        )

        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "preset_ref", preset_id: preset_1.id }
            ]
          }
        )

        expect { executor.execute }.not_to raise_error
      end

      it "無効なプリセットIDが指定された場合は無視される" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "preset_ref", preset_id: 999999 }
            ]
          }
        )
        results = executor.execute

        expect(results.size).to eq(3)
      end
    end

    context "ソートとリミット" do
      it "指定カラムでソートされる" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: []
          },
          display_json: { sort_by: "roe", sort_order: "desc" }
        )
        results = executor.execute

        roe_values = results.map { |r| r[:metric].roe.to_f }
        expect(roe_values).to eq(roe_values.sort.reverse)
      end

      it "limit制限が適用される" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: []
          },
          display_json: { limit: 2 }
        )
        results = executor.execute

        expect(results.size).to eq(2)
      end

      it "limitが500を超えない" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: []
          },
          display_json: { limit: 1000 }
        )
        # 実際のデータが3件しかないため件数は3以下だが、内部のlimitが500であることをテスト
        scope = executor.build_base_scope
        limited_scope = executor.send(:apply_limit, scope)

        expect(limited_scope.limit_value).to eq(500)
      end
    end

    context "複合条件" do
      it "連続増収増益プリセットの条件が正しく動作する" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_range", field: "consecutive_revenue_growth", min: 6 },
              { type: "metric_range", field: "consecutive_profit_growth", min: 6 },
            ]
          },
          display_json: { sort_by: "revenue_yoy", sort_order: "desc" }
        )
        results = executor.execute

        companies = results.map { |r| r[:company] }
        expect(companies).to contain_exactly(company_a, company_c)
        # revenue_yoy descでソートされていること
        expect(results.first[:company]).to eq(company_c) # 0.25 > 0.15
      end

      it "高ROE・低PBRバリュー条件が正しく動作する" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_range", field: "roe", min: 0.10 },
              { type: "data_json_range", field: "pbr", max: 1.5 },
              { type: "metric_boolean", field: "operating_cf_positive", value: true },
            ]
          },
          display_json: { sort_by: "roe", sort_order: "desc" }
        )
        results = executor.execute

        expect(results.map { |r| r[:company] }).to contain_exactly(company_a)
      end
    end

    context "ホワイトリスト検証" do
      it "不正なmetric_rangeフィールドは無視される" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_range", field: "invalid_field", min: 0 }
            ]
          }
        )
        results = executor.execute

        expect(results.size).to eq(3)
      end

      it "不正なcompany_attributeフィールドは無視される" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "company_attribute", field: "hacked_column", values: ["test"] }
            ]
          }
        )
        results = executor.execute

        expect(results.size).to eq(3)
      end
    end

    context "結果の構造" do
      it "company と metric を含むHashの配列を返す" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_range", field: "roe", min: 0.10 }
            ]
          }
        )
        results = executor.execute

        expect(results).to be_an(Array)
        expect(results.first).to have_key(:company)
        expect(results.first).to have_key(:metric)
        expect(results.first[:company]).to be_a(Company)
        expect(results.first[:metric]).to be_a(FinancialMetric)
      end
    end

    context "temporal条件" do
      # company_a に過去期間のメトリクスを追加（5年分の履歴）
      # ROE: 0.11, 0.12, 0.13, 0.14, 0.125(最新期)
      # free_cf_positive: true throughout
      before do
        [
          { fiscal_year_end: "2021-03-31", roe: 0.11, operating_margin: 0.10, free_cf_positive: true },
          { fiscal_year_end: "2022-03-31", roe: 0.12, operating_margin: 0.12, free_cf_positive: true },
          { fiscal_year_end: "2023-03-31", roe: 0.13, operating_margin: 0.13, free_cf_positive: true },
          { fiscal_year_end: "2024-03-31", roe: 0.14, operating_margin: 0.14, free_cf_positive: true },
        ].each do |attrs|
          fv = FinancialValue.create!(
            company: company_a,
            fiscal_year_end: attrs[:fiscal_year_end],
            scope: :consolidated,
            period_type: :annual,
            net_sales: 80_000_000
          )
          FinancialMetric.create!(
            company: company_a,
            financial_value: fv,
            fiscal_year_end: attrs[:fiscal_year_end],
            scope: :consolidated,
            period_type: :annual,
            roe: attrs[:roe],
            operating_margin: attrs[:operating_margin],
            free_cf_positive: attrs[:free_cf_positive]
          )
        end

        # company_b に過去期間のメトリクスを追加
        # ROE: 0.06, 0.05, 0.08, 0.07, 0.075(最新期)
        # free_cf_positive: false -> false -> false -> false -> false(最新期)
        [
          { fiscal_year_end: "2021-03-31", roe: 0.06, operating_margin: 0.08, free_cf_positive: false },
          { fiscal_year_end: "2022-03-31", roe: 0.05, operating_margin: 0.09, free_cf_positive: false },
          { fiscal_year_end: "2023-03-31", roe: 0.08, operating_margin: 0.10, free_cf_positive: false },
          { fiscal_year_end: "2024-03-31", roe: 0.07, operating_margin: 0.11, free_cf_positive: false },
        ].each do |attrs|
          fv = FinancialValue.create!(
            company: company_b,
            fiscal_year_end: attrs[:fiscal_year_end],
            scope: :consolidated,
            period_type: :annual,
            net_sales: 40_000_000
          )
          FinancialMetric.create!(
            company: company_b,
            financial_value: fv,
            fiscal_year_end: attrs[:fiscal_year_end],
            scope: :consolidated,
            period_type: :annual,
            roe: attrs[:roe],
            operating_margin: attrs[:operating_margin],
            free_cf_positive: attrs[:free_cf_positive]
          )
        end
      end

      it "temporal条件と既存条件（metric_range等）の組み合わせで動作する" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              { type: "metric_range", field: "roe", min: 0.05 },
              {
                type: "temporal",
                temporal_type: "at_least_n_of_m",
                field: "roe",
                threshold: 0.10,
                comparison: "gte",
                n: 4,
                m: 5
              }
            ]
          }
        )
        results = executor.execute

        # company_a: ROE history 0.11,0.12,0.13,0.14,0.125 => 5/5 >= 0.10 => pass
        # company_b: ROE history 0.06,0.05,0.08,0.07,0.075 => 0/5 >= 0.10 => fail
        # company_c: no history => fail
        expect(results.map { |r| r[:company] }).to contain_exactly(company_a)
      end

      it "temporal条件のみの場合でも動作する" do
        executor = described_class.new(
          conditions_json: {
            scope_type: "consolidated", period_type: "annual", logic: "and",
            conditions: [
              {
                type: "temporal",
                temporal_type: "consecutive",
                field: "operating_margin",
                direction: "improving",
                n: 3
              }
            ]
          }
        )
        results = executor.execute

        # company_a: operating_margin 0.10,0.12,0.13,0.14,0.15 => last 4: 0.12,0.13,0.14,0.15 => 3 consecutive improving => pass
        # company_b: operating_margin 0.08,0.09,0.10,0.11,0.10 => last 4: 0.09,0.10,0.11,0.10 => 0.11->0.10 not improving => fail
        # company_c: no history => fail
        expect(results.map { |r| r[:company] }).to contain_exactly(company_a)
      end
    end
  end
end
