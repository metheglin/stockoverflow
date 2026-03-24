require "rails_helper"

RSpec.describe FinancialMetric do
  describe ".compute_yoy" do
    it "正の成長率を算出する" do
      expect(FinancialMetric.compute_yoy(115, 100)).to eq(BigDecimal("0.15"))
    end

    it "負の成長率を算出する" do
      expect(FinancialMetric.compute_yoy(85, 100)).to eq(BigDecimal("-0.15"))
    end

    it "前期が赤字→今期黒字の場合も正しく算出する" do
      # 前期 -100 → 今期 50: 変化量150、|前期|100 → 1.5 (150%)
      expect(FinancialMetric.compute_yoy(50, -100)).to eq(BigDecimal("1.5"))
    end

    it "前期が0の場合はnilを返す" do
      expect(FinancialMetric.compute_yoy(100, 0)).to be_nil
    end

    it "当期がnilの場合はnilを返す" do
      expect(FinancialMetric.compute_yoy(nil, 100)).to be_nil
    end

    it "前期がnilの場合はnilを返す" do
      expect(FinancialMetric.compute_yoy(100, nil)).to be_nil
    end
  end

  describe ".safe_divide" do
    it "正常な除算を実行する" do
      expect(FinancialMetric.safe_divide(100, 1000)).to eq(BigDecimal("0.1"))
    end

    it "分母が0の場合はnilを返す" do
      expect(FinancialMetric.safe_divide(100, 0)).to be_nil
    end

    it "分子がnilの場合はnilを返す" do
      expect(FinancialMetric.safe_divide(nil, 100)).to be_nil
    end

    it "分母がnilの場合はnilを返す" do
      expect(FinancialMetric.safe_divide(100, nil)).to be_nil
    end
  end

  describe ".get_growth_metrics" do
    it "全YoY指標を算出する" do
      current_fv = FinancialValue.new(
        net_sales: 1150, operating_income: 240, ordinary_income: 260,
        net_income: 180, eps: BigDecimal("66.76")
      )
      previous_fv = FinancialValue.new(
        net_sales: 1000, operating_income: 200, ordinary_income: 220,
        net_income: 150, eps: BigDecimal("55.50")
      )

      result = FinancialMetric.get_growth_metrics(current_fv, previous_fv)

      expect(result[:revenue_yoy]).to eq(BigDecimal("0.15"))
      expect(result[:operating_income_yoy]).to eq(BigDecimal("0.2"))
      expect(result[:net_income_yoy]).to eq(BigDecimal("0.2"))
      expect(result[:eps_yoy]).to be_a(BigDecimal)
    end

    it "前期がnilの場合は空Hashを返す" do
      current_fv = FinancialValue.new(net_sales: 1150)
      result = FinancialMetric.get_growth_metrics(current_fv, nil)

      expect(result).to eq({})
    end
  end

  describe ".get_profitability_metrics" do
    it "収益性指標を算出する" do
      fv = FinancialValue.new(
        net_sales: 10000, operating_income: 1500, ordinary_income: 1600,
        net_income: 1000, total_assets: 50000, net_assets: 20000,
      )

      result = FinancialMetric.get_profitability_metrics(fv)

      expect(result[:operating_margin]).to eq(BigDecimal("0.15"))
      expect(result[:ordinary_margin]).to eq(BigDecimal("0.16"))
      expect(result[:net_margin]).to eq(BigDecimal("0.1"))
      expect(result[:roe]).to eq(BigDecimal("0.05"))
      expect(result[:roa]).to eq(BigDecimal("0.02"))
    end

    it "net_salesが0の場合マージン系はnilになる" do
      fv = FinancialValue.new(net_sales: 0, operating_income: 100, net_income: 50,
                              total_assets: 1000, net_assets: 500)

      result = FinancialMetric.get_profitability_metrics(fv)

      expect(result[:operating_margin]).to be_nil
      expect(result[:net_margin]).to be_nil
    end
  end

  describe ".get_financial_health_metrics" do
    it "全財務健全性指標を算出する" do
      fv = FinancialValue.new(
        total_assets: 10_000_000_000,
        net_assets: 4_000_000_000,
        cash_and_equivalents: 1_000_000_000,
      )
      allow(fv).to receive(:current_assets).and_return(5_000_000_000)
      allow(fv).to receive(:current_liabilities).and_return(3_000_000_000)
      allow(fv).to receive(:noncurrent_liabilities).and_return(2_000_000_000)
      allow(fv).to receive(:shareholders_equity).and_return(3_500_000_000)

      result = FinancialMetric.get_financial_health_metrics(fv)

      # 流動比率 = 5B / 3B = 1.6667
      expect(result["current_ratio"]).to be_within(0.001).of(1.6667)
      # 負債資本倍率 = (3B + 2B) / 3.5B = 1.4286
      expect(result["debt_to_equity"]).to be_within(0.001).of(1.4286)
      # ネット負債資本倍率 = ((10B - 4B) - 1B) / 3.5B = 5B / 3.5B = 1.4286
      expect(result["net_debt_to_equity"]).to be_within(0.001).of(1.4286)
    end

    it "current_assetsがnilの場合はcurrent_ratioをスキップする" do
      fv = FinancialValue.new(
        total_assets: 10_000_000_000,
        net_assets: 4_000_000_000,
        cash_and_equivalents: 1_000_000_000,
      )
      allow(fv).to receive(:current_assets).and_return(nil)
      allow(fv).to receive(:current_liabilities).and_return(3_000_000_000)
      allow(fv).to receive(:noncurrent_liabilities).and_return(2_000_000_000)
      allow(fv).to receive(:shareholders_equity).and_return(3_500_000_000)

      result = FinancialMetric.get_financial_health_metrics(fv)

      expect(result).not_to have_key("current_ratio")
      expect(result).to have_key("debt_to_equity")
      expect(result).to have_key("net_debt_to_equity")
    end

    it "current_liabilitiesが0の場合はcurrent_ratioをスキップする" do
      fv = FinancialValue.new(
        total_assets: 10_000_000_000,
        net_assets: 4_000_000_000,
        cash_and_equivalents: 1_000_000_000,
      )
      allow(fv).to receive(:current_assets).and_return(5_000_000_000)
      allow(fv).to receive(:current_liabilities).and_return(0)
      allow(fv).to receive(:noncurrent_liabilities).and_return(2_000_000_000)
      allow(fv).to receive(:shareholders_equity).and_return(3_500_000_000)

      result = FinancialMetric.get_financial_health_metrics(fv)

      expect(result).not_to have_key("current_ratio")
    end

    it "shareholders_equityが0の場合はdebt_to_equityとnet_debt_to_equityをスキップする" do
      fv = FinancialValue.new(
        total_assets: 10_000_000_000,
        net_assets: 4_000_000_000,
        cash_and_equivalents: 1_000_000_000,
      )
      allow(fv).to receive(:current_assets).and_return(5_000_000_000)
      allow(fv).to receive(:current_liabilities).and_return(3_000_000_000)
      allow(fv).to receive(:noncurrent_liabilities).and_return(2_000_000_000)
      allow(fv).to receive(:shareholders_equity).and_return(0)

      result = FinancialMetric.get_financial_health_metrics(fv)

      expect(result).to have_key("current_ratio")
      expect(result).not_to have_key("debt_to_equity")
      expect(result).not_to have_key("net_debt_to_equity")
    end

    it "全値がnilの場合は空Hashを返す" do
      fv = FinancialValue.new(
        total_assets: nil,
        net_assets: nil,
        cash_and_equivalents: nil,
      )
      allow(fv).to receive(:current_assets).and_return(nil)
      allow(fv).to receive(:current_liabilities).and_return(nil)
      allow(fv).to receive(:noncurrent_liabilities).and_return(nil)
      allow(fv).to receive(:shareholders_equity).and_return(nil)

      result = FinancialMetric.get_financial_health_metrics(fv)

      expect(result).to eq({})
    end
  end

  describe ".get_efficiency_metrics" do
    it "全効率性指標を算出する" do
      fv = FinancialValue.new(
        net_sales: 10_000_000_000,
        total_assets: 20_000_000_000,
      )
      allow(fv).to receive(:gross_profit).and_return(4_000_000_000)
      allow(fv).to receive(:sga_expenses).and_return(2_500_000_000)

      result = FinancialMetric.get_efficiency_metrics(fv)

      # 総資産回転率 = 10B / 20B = 0.5
      expect(result["asset_turnover"]).to eq(0.5)
      # 売上総利益率 = 4B / 10B = 0.4
      expect(result["gross_margin"]).to eq(0.4)
      # 販管費率 = 2.5B / 10B = 0.25
      expect(result["sga_ratio"]).to eq(0.25)
    end

    it "gross_profitがnilの場合はgross_marginをスキップする" do
      fv = FinancialValue.new(
        net_sales: 10_000_000_000,
        total_assets: 20_000_000_000,
      )
      allow(fv).to receive(:gross_profit).and_return(nil)
      allow(fv).to receive(:sga_expenses).and_return(2_500_000_000)

      result = FinancialMetric.get_efficiency_metrics(fv)

      expect(result).to have_key("asset_turnover")
      expect(result).not_to have_key("gross_margin")
      expect(result).to have_key("sga_ratio")
    end

    it "net_salesが0の場合は全指標をスキップする" do
      fv = FinancialValue.new(
        net_sales: 0,
        total_assets: 20_000_000_000,
      )
      allow(fv).to receive(:gross_profit).and_return(4_000_000_000)
      allow(fv).to receive(:sga_expenses).and_return(2_500_000_000)

      result = FinancialMetric.get_efficiency_metrics(fv)

      expect(result).to have_key("asset_turnover")
      expect(result).not_to have_key("gross_margin")
      expect(result).not_to have_key("sga_ratio")
    end

    it "total_assetsがnilの場合はasset_turnoverをスキップする" do
      fv = FinancialValue.new(
        net_sales: 10_000_000_000,
        total_assets: nil,
      )
      allow(fv).to receive(:gross_profit).and_return(4_000_000_000)
      allow(fv).to receive(:sga_expenses).and_return(2_500_000_000)

      result = FinancialMetric.get_efficiency_metrics(fv)

      expect(result).not_to have_key("asset_turnover")
      expect(result).to have_key("gross_margin")
      expect(result).to have_key("sga_ratio")
    end

    it "全値がnilの場合は空Hashを返す" do
      fv = FinancialValue.new(
        net_sales: nil,
        total_assets: nil,
      )
      allow(fv).to receive(:gross_profit).and_return(nil)
      allow(fv).to receive(:sga_expenses).and_return(nil)

      result = FinancialMetric.get_efficiency_metrics(fv)

      expect(result).to eq({})
    end
  end

  describe ".get_cf_metrics" do
    it "CF指標を算出する" do
      fv = FinancialValue.new(operating_cf: 5000, investing_cf: -2000)
      result = FinancialMetric.get_cf_metrics(fv)

      expect(result[:free_cf]).to eq(3000)
      expect(result[:operating_cf_positive]).to eq(true)
      expect(result[:investing_cf_negative]).to eq(true)
      expect(result[:free_cf_positive]).to eq(true)
    end

    it "フリーCFが負の場合" do
      fv = FinancialValue.new(operating_cf: 2000, investing_cf: -5000)
      result = FinancialMetric.get_cf_metrics(fv)

      expect(result[:free_cf]).to eq(-3000)
      expect(result[:free_cf_positive]).to eq(false)
    end

    it "CF値がnilの場合" do
      fv = FinancialValue.new(operating_cf: nil, investing_cf: nil)
      result = FinancialMetric.get_cf_metrics(fv)

      expect(result[:free_cf]).to be_nil
      expect(result[:operating_cf_positive]).to be_nil
    end
  end

  describe ".get_consecutive_metrics" do
    it "増収増益の場合は前期+1" do
      growth = { revenue_yoy: BigDecimal("0.1"), net_income_yoy: BigDecimal("0.2") }
      prev_metric = FinancialMetric.new(
        consecutive_revenue_growth: 3,
        consecutive_profit_growth: 2,
      )

      result = FinancialMetric.get_consecutive_metrics(growth, prev_metric)

      expect(result[:consecutive_revenue_growth]).to eq(4)
      expect(result[:consecutive_profit_growth]).to eq(3)
    end

    it "減収の場合は0にリセット" do
      growth = { revenue_yoy: BigDecimal("-0.05"), net_income_yoy: BigDecimal("0.1") }
      prev_metric = FinancialMetric.new(
        consecutive_revenue_growth: 5,
        consecutive_profit_growth: 3,
      )

      result = FinancialMetric.get_consecutive_metrics(growth, prev_metric)

      expect(result[:consecutive_revenue_growth]).to eq(0)
      expect(result[:consecutive_profit_growth]).to eq(4)
    end

    it "前期metricがnilの場合は初期値" do
      growth = { revenue_yoy: BigDecimal("0.1"), net_income_yoy: BigDecimal("0.2") }
      result = FinancialMetric.get_consecutive_metrics(growth, nil)

      expect(result[:consecutive_revenue_growth]).to eq(1)
      expect(result[:consecutive_profit_growth]).to eq(1)
    end

    it "YoYがnilの場合は0" do
      growth = { revenue_yoy: nil, net_income_yoy: nil }
      result = FinancialMetric.get_consecutive_metrics(growth, nil)

      expect(result[:consecutive_revenue_growth]).to eq(0)
      expect(result[:consecutive_profit_growth]).to eq(0)
    end
  end

  describe ".get_expected_consecutive" do
    it "YoYが正の場合は前期+1を返す" do
      expect(FinancialMetric.get_expected_consecutive(3, BigDecimal("0.1"))).to eq(4)
    end

    it "YoYが負の場合は0を返す" do
      expect(FinancialMetric.get_expected_consecutive(5, BigDecimal("-0.05"))).to eq(0)
    end

    it "YoYが0の場合は0を返す" do
      expect(FinancialMetric.get_expected_consecutive(3, BigDecimal("0"))).to eq(0)
    end

    it "YoYがnilの場合は0を返す" do
      expect(FinancialMetric.get_expected_consecutive(3, nil)).to eq(0)
    end

    it "前期が0でYoYが正の場合は1を返す" do
      expect(FinancialMetric.get_expected_consecutive(0, BigDecimal("0.2"))).to eq(1)
    end
  end

  describe ".detect_consecutive_anomalies" do
    it "正常な連続増収増益シーケンスの場合は空配列を返す" do
      metrics = [
        { fiscal_year_end: "2023-03-31", revenue_yoy: BigDecimal("0.1"), net_income_yoy: BigDecimal("0.15"),
          consecutive_revenue_growth: 1, consecutive_profit_growth: 1 },
        { fiscal_year_end: "2024-03-31", revenue_yoy: BigDecimal("0.08"), net_income_yoy: BigDecimal("0.12"),
          consecutive_revenue_growth: 2, consecutive_profit_growth: 2 },
        { fiscal_year_end: "2025-03-31", revenue_yoy: BigDecimal("0.05"), net_income_yoy: BigDecimal("0.10"),
          consecutive_revenue_growth: 3, consecutive_profit_growth: 3 },
      ]

      expect(FinancialMetric.detect_consecutive_anomalies(metrics)).to eq([])
    end

    it "リセットを含む正常シーケンスの場合は空配列を返す" do
      metrics = [
        { fiscal_year_end: "2023-03-31", revenue_yoy: BigDecimal("0.1"), net_income_yoy: BigDecimal("0.15"),
          consecutive_revenue_growth: 2, consecutive_profit_growth: 3 },
        { fiscal_year_end: "2024-03-31", revenue_yoy: BigDecimal("-0.05"), net_income_yoy: BigDecimal("0.10"),
          consecutive_revenue_growth: 0, consecutive_profit_growth: 4 },
        { fiscal_year_end: "2025-03-31", revenue_yoy: BigDecimal("0.03"), net_income_yoy: BigDecimal("-0.02"),
          consecutive_revenue_growth: 1, consecutive_profit_growth: 0 },
      ]

      expect(FinancialMetric.detect_consecutive_anomalies(metrics)).to eq([])
    end

    it "連続増収期数が飛んでいる場合に不整合を検出する" do
      metrics = [
        { fiscal_year_end: "2023-03-31", revenue_yoy: BigDecimal("0.1"), net_income_yoy: BigDecimal("0.15"),
          consecutive_revenue_growth: 1, consecutive_profit_growth: 1 },
        { fiscal_year_end: "2024-03-31", revenue_yoy: BigDecimal("0.08"), net_income_yoy: BigDecimal("0.12"),
          consecutive_revenue_growth: 5, consecutive_profit_growth: 2 },
      ]

      anomalies = FinancialMetric.detect_consecutive_anomalies(metrics)

      expect(anomalies.size).to eq(1)
      expect(anomalies[0][:field]).to eq(:consecutive_revenue_growth)
      expect(anomalies[0][:expected]).to eq(2)
      expect(anomalies[0][:actual]).to eq(5)
      expect(anomalies[0][:fiscal_year_end]).to eq("2024-03-31")
    end

    it "減収時にリセットされていない場合に不整合を検出する" do
      metrics = [
        { fiscal_year_end: "2023-03-31", revenue_yoy: BigDecimal("0.1"), net_income_yoy: BigDecimal("0.15"),
          consecutive_revenue_growth: 3, consecutive_profit_growth: 2 },
        { fiscal_year_end: "2024-03-31", revenue_yoy: BigDecimal("-0.10"), net_income_yoy: BigDecimal("-0.05"),
          consecutive_revenue_growth: 4, consecutive_profit_growth: 3 },
      ]

      anomalies = FinancialMetric.detect_consecutive_anomalies(metrics)

      expect(anomalies.size).to eq(2)
      expect(anomalies[0][:field]).to eq(:consecutive_revenue_growth)
      expect(anomalies[0][:expected]).to eq(0)
      expect(anomalies[0][:actual]).to eq(4)
      expect(anomalies[1][:field]).to eq(:consecutive_profit_growth)
      expect(anomalies[1][:expected]).to eq(0)
      expect(anomalies[1][:actual]).to eq(3)
    end

    it "要素が1つの場合は空配列を返す" do
      metrics = [
        { fiscal_year_end: "2024-03-31", revenue_yoy: BigDecimal("0.1"), net_income_yoy: BigDecimal("0.15"),
          consecutive_revenue_growth: 1, consecutive_profit_growth: 1 },
      ]

      expect(FinancialMetric.detect_consecutive_anomalies(metrics)).to eq([])
    end

    it "空配列の場合は空配列を返す" do
      expect(FinancialMetric.detect_consecutive_anomalies([])).to eq([])
    end
  end

  describe ".get_ev_ebitda" do
    it "EV/EBITDAを正常に算出する" do
      fv = FinancialValue.new(
        shares_outstanding: 1_000_000,
        operating_income: 500_000_000,
        total_assets: 10_000_000_000,
        net_assets: 4_000_000_000,
        cash_and_equivalents: 1_000_000_000,
      )
      stock_price = 2000.0

      result = FinancialMetric.get_ev_ebitda(fv, stock_price)

      # EV = 2000 * 1_000_000 + (10B - 4B) - 1B = 2B + 6B - 1B = 7B
      # EBITDA = 500_000_000
      # EV/EBITDA = 7_000_000_000 / 500_000_000 = 14.0
      expect(result["ev_ebitda"]).to eq(14.0)
    end

    it "株価がnilの場合は空Hashを返す" do
      fv = FinancialValue.new(
        shares_outstanding: 1_000_000,
        operating_income: 500_000_000,
        total_assets: 10_000_000_000,
        net_assets: 4_000_000_000,
      )

      expect(FinancialMetric.get_ev_ebitda(fv, nil)).to eq({})
    end

    it "cash_and_equivalentsがnilの場合は0として扱う" do
      fv = FinancialValue.new(
        shares_outstanding: 1_000_000,
        operating_income: 500_000_000,
        total_assets: 10_000_000_000,
        net_assets: 4_000_000_000,
        cash_and_equivalents: nil,
      )
      stock_price = 2000.0

      result = FinancialMetric.get_ev_ebitda(fv, stock_price)

      # EV = 2B + 6B - 0 = 8B
      # EBITDA = 500M
      # EV/EBITDA = 16.0
      expect(result["ev_ebitda"]).to eq(16.0)
    end

    it "shares_outstandingがnilの場合は空Hashを返す" do
      fv = FinancialValue.new(
        shares_outstanding: nil,
        operating_income: 500_000_000,
        total_assets: 10_000_000_000,
        net_assets: 4_000_000_000,
      )

      expect(FinancialMetric.get_ev_ebitda(fv, 2000.0)).to eq({})
    end
  end

  describe ".get_surprise_metrics" do
    it "ポジティブサプライズの乖離率を算出する" do
      current_fv = FinancialValue.new(
        net_sales: 1_100_000_000,
        operating_income: 220_000_000,
        net_income: 150_000_000,
        eps: BigDecimal("75.0"),
      )
      previous_fv = FinancialValue.new
      allow(previous_fv).to receive(:data_json).and_return({
        "forecast_net_sales" => 1_000_000_000,
        "forecast_operating_income" => 200_000_000,
        "forecast_net_income" => 130_000_000,
        "forecast_eps" => 65.0,
      })

      result = FinancialMetric.get_surprise_metrics(current_fv, previous_fv)

      expect(result["revenue_surprise"]).to eq(0.1)
      expect(result["operating_income_surprise"]).to eq(0.1)
      expect(result["net_income_surprise"]).to be_within(0.001).of(0.1538)
      expect(result["eps_surprise"]).to be_within(0.001).of(0.1538)
    end

    it "ネガティブサプライズの乖離率を算出する" do
      current_fv = FinancialValue.new(
        net_sales: 900_000_000,
        operating_income: 180_000_000,
        net_income: 100_000_000,
        eps: BigDecimal("50.0"),
      )
      previous_fv = FinancialValue.new
      allow(previous_fv).to receive(:data_json).and_return({
        "forecast_net_sales" => 1_000_000_000,
        "forecast_operating_income" => 200_000_000,
        "forecast_net_income" => 130_000_000,
        "forecast_eps" => 65.0,
      })

      result = FinancialMetric.get_surprise_metrics(current_fv, previous_fv)

      expect(result["revenue_surprise"]).to eq(-0.1)
      expect(result["operating_income_surprise"]).to eq(-0.1)
      expect(result["net_income_surprise"]).to be_within(0.001).of(-0.2308)
      expect(result["eps_surprise"]).to be_within(0.001).of(-0.2308)
    end

    it "前期がnilの場合は空Hashを返す" do
      current_fv = FinancialValue.new(net_sales: 1_000_000_000)

      expect(FinancialMetric.get_surprise_metrics(current_fv, nil)).to eq({})
    end

    it "前期の予想がnilの場合は該当キーを含めない" do
      current_fv = FinancialValue.new(
        net_sales: 1_100_000_000,
        operating_income: 220_000_000,
      )
      previous_fv = FinancialValue.new
      allow(previous_fv).to receive(:data_json).and_return({
        "forecast_net_sales" => 1_000_000_000,
      })

      result = FinancialMetric.get_surprise_metrics(current_fv, previous_fv)

      expect(result.key?("revenue_surprise")).to eq(true)
      expect(result.key?("operating_income_surprise")).to eq(false)
      expect(result.key?("net_income_surprise")).to eq(false)
      expect(result.key?("eps_surprise")).to eq(false)
    end
  end

  describe ".get_valuation_metrics" do
    it "バリュエーション指標を算出する" do
      fv = FinancialValue.new(
        eps: BigDecimal("66.76"),
        bps: BigDecimal("380.50"),
        net_sales: 100_000_000_000,
        shares_outstanding: 524_000_000,
      )
      allow(fv).to receive(:data_json).and_return({ "dividend_per_share_annual" => 50.0 })

      result = FinancialMetric.get_valuation_metrics(fv, 2000.0)

      expect(result["per"]).to be_within(0.1).of(30.0)
      expect(result["pbr"]).to be_within(0.01).of(5.26)
      expect(result["psr"]).to be_a(Float)
      expect(result["dividend_yield"]).to eq(0.025)
    end

    it "株価がnilの場合は空Hashを返す" do
      fv = FinancialValue.new(eps: BigDecimal("66.76"))
      result = FinancialMetric.get_valuation_metrics(fv, nil)

      expect(result).to eq({})
    end
  end
end
