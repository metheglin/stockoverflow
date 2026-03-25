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

  describe ".get_standalone_quarter_value" do
    it "前四半期がnilの場合（Q1）は累計値をそのまま返す" do
      fv = FinancialValue.new(net_sales: 5_000_000_000)

      result = FinancialMetric.get_standalone_quarter_value(fv, nil, :net_sales)

      expect(result).to eq(5_000_000_000)
    end

    it "前四半期が存在する場合は差分を返す" do
      q2_fv = FinancialValue.new(net_sales: 12_000_000_000)
      q1_fv = FinancialValue.new(net_sales: 5_000_000_000)

      result = FinancialMetric.get_standalone_quarter_value(q2_fv, q1_fv, :net_sales)

      expect(result).to eq(7_000_000_000)
    end

    it "当期値がnilの場合はnilを返す" do
      fv = FinancialValue.new(net_sales: nil)
      prev_fv = FinancialValue.new(net_sales: 5_000_000_000)

      result = FinancialMetric.get_standalone_quarter_value(fv, prev_fv, :net_sales)

      expect(result).to be_nil
    end

    it "前四半期の値がnilの場合はnilを返す" do
      fv = FinancialValue.new(net_sales: 12_000_000_000)
      prev_fv = FinancialValue.new(net_sales: nil)

      result = FinancialMetric.get_standalone_quarter_value(fv, prev_fv, :net_sales)

      expect(result).to be_nil
    end

    it "Q3の場合はQ3累計 - Q2累計を返す" do
      q3_fv = FinancialValue.new(operating_income: 900_000_000)
      q2_fv = FinancialValue.new(operating_income: 550_000_000)

      result = FinancialMetric.get_standalone_quarter_value(q3_fv, q2_fv, :operating_income)

      expect(result).to eq(350_000_000)
    end
  end

  describe ".get_quarterly_yoy_metrics" do
    it "Q2の単独四半期YoYを算出する" do
      # 当期: Q2累計 12B, Q1累計 5B → Q2単独 7B
      # 前年: Q2累計 10B, Q1累計 4B → Q2単独 6B
      # 売上YoY = (7B - 6B) / 6B = 0.1667
      current_q2 = FinancialValue.new(
        period_type: :q2,
        net_sales: 12_000_000_000,
        operating_income: 1_400_000_000,
        net_income: 900_000_000,
      )
      current_q1 = FinancialValue.new(
        period_type: :q1,
        net_sales: 5_000_000_000,
        operating_income: 600_000_000,
        net_income: 400_000_000,
      )
      prior_q2 = FinancialValue.new(
        period_type: :q2,
        net_sales: 10_000_000_000,
        operating_income: 1_200_000_000,
        net_income: 800_000_000,
      )
      prior_q1 = FinancialValue.new(
        period_type: :q1,
        net_sales: 4_000_000_000,
        operating_income: 500_000_000,
        net_income: 350_000_000,
      )

      result = FinancialMetric.get_quarterly_yoy_metrics(
        current_q2, prior_q2,
        current_prev_quarter_fv: current_q1,
        prior_prev_quarter_fv: prior_q1,
      )

      # Q2単独売上: 7B vs 6B → YoY = 1/6 = 0.1667
      expect(result["standalone_quarter_revenue_yoy"]).to be_within(0.001).of(0.1667)
      # Q2単独営業利益: 800M vs 700M → YoY = 100M/700M = 0.1429
      expect(result["standalone_quarter_operating_income_yoy"]).to be_within(0.001).of(0.1429)
      # Q2単独純利益: 500M vs 450M → YoY = 50M/450M = 0.1111
      expect(result["standalone_quarter_net_income_yoy"]).to be_within(0.001).of(0.1111)
    end

    it "Q1の場合は累計値ベースでYoYを算出する" do
      current_q1 = FinancialValue.new(
        period_type: :q1,
        net_sales: 5_500_000_000,
        operating_income: 700_000_000,
        net_income: 450_000_000,
      )
      prior_q1 = FinancialValue.new(
        period_type: :q1,
        net_sales: 5_000_000_000,
        operating_income: 600_000_000,
        net_income: 400_000_000,
      )

      result = FinancialMetric.get_quarterly_yoy_metrics(current_q1, prior_q1)

      # Q1は累計=単独。売上YoY = 500M / 5B = 0.1
      expect(result["standalone_quarter_revenue_yoy"]).to be_within(0.001).of(0.1)
      expect(result["standalone_quarter_operating_income_yoy"]).to be_within(0.001).of(0.1667)
      expect(result["standalone_quarter_net_income_yoy"]).to be_within(0.001).of(0.125)
    end

    it "前年同四半期がnilの場合は空Hashを返す" do
      current_q2 = FinancialValue.new(
        period_type: :q2,
        net_sales: 12_000_000_000,
      )

      result = FinancialMetric.get_quarterly_yoy_metrics(current_q2, nil)

      expect(result).to eq({})
    end

    it "annual期の場合は空Hashを返す" do
      current_annual = FinancialValue.new(
        period_type: :annual,
        net_sales: 20_000_000_000,
      )
      prior_annual = FinancialValue.new(
        period_type: :annual,
        net_sales: 18_000_000_000,
      )

      result = FinancialMetric.get_quarterly_yoy_metrics(current_annual, prior_annual)

      expect(result).to eq({})
    end

    it "前四半期レコードが欠損している場合は累計ベースのYoYを算出する" do
      # Q2だが前四半期(Q1)がない → 累計値をそのまま使う
      current_q2 = FinancialValue.new(
        period_type: :q2,
        net_sales: 12_000_000_000,
        operating_income: 1_400_000_000,
        net_income: 900_000_000,
      )
      prior_q2 = FinancialValue.new(
        period_type: :q2,
        net_sales: 10_000_000_000,
        operating_income: 1_200_000_000,
        net_income: 800_000_000,
      )

      result = FinancialMetric.get_quarterly_yoy_metrics(
        current_q2, prior_q2,
        current_prev_quarter_fv: nil,
        prior_prev_quarter_fv: nil,
      )

      # 累計ベース: 12B vs 10B → 0.2
      expect(result["standalone_quarter_revenue_yoy"]).to be_within(0.001).of(0.2)
    end

    it "当期の前四半期のみ欠損している場合は値がnilとなりスキップする" do
      current_q2 = FinancialValue.new(
        period_type: :q2,
        net_sales: 12_000_000_000,
        operating_income: nil,
        net_income: nil,
      )
      prior_q2 = FinancialValue.new(
        period_type: :q2,
        net_sales: 10_000_000_000,
        operating_income: 1_200_000_000,
        net_income: 800_000_000,
      )
      prior_q1 = FinancialValue.new(
        period_type: :q1,
        net_sales: 4_000_000_000,
        operating_income: 500_000_000,
        net_income: 350_000_000,
      )

      result = FinancialMetric.get_quarterly_yoy_metrics(
        current_q2, prior_q2,
        current_prev_quarter_fv: nil,
        prior_prev_quarter_fv: prior_q1,
      )

      # net_sales: current has no prev_quarter → standalone=cumulative(12B), prior: 10B-4B=6B → 12B vs 6B = 1.0
      expect(result["standalone_quarter_revenue_yoy"]).to be_within(0.001).of(1.0)
      # operating_income: current is nil → skip
      expect(result).not_to have_key("standalone_quarter_operating_income_yoy")
      expect(result).not_to have_key("standalone_quarter_net_income_yoy")
    end

    it "前年同四半期の値が0の場合はその指標をスキップする" do
      current_q1 = FinancialValue.new(
        period_type: :q1,
        net_sales: 5_000_000_000,
        operating_income: 100_000_000,
        net_income: 50_000_000,
      )
      prior_q1 = FinancialValue.new(
        period_type: :q1,
        net_sales: 0,
        operating_income: 0,
        net_income: 0,
      )

      result = FinancialMetric.get_quarterly_yoy_metrics(current_q1, prior_q1)

      expect(result).to eq({})
    end
  end

  describe ".percentile_ranks" do
    it "均等分布の値に対して正しいpercentile rankを返す" do
      result = FinancialMetric.percentile_ranks([10, 20, 30, 40, 50])
      expect(result).to eq([0.0, 25.0, 50.0, 75.0, 100.0])
    end

    it "逆順の値でも正しいpercentile rankを返す" do
      result = FinancialMetric.percentile_ranks([50, 40, 30, 20, 10])
      expect(result).to eq([100.0, 75.0, 50.0, 25.0, 0.0])
    end

    it "同値を含む場合は平均順位ベースのpercentileを返す" do
      result = FinancialMetric.percentile_ranks([10, 20, 20, 30])
      # 20が2つ: rank 1と2の平均=1.5、n-1=3 → 1.5/3*100=50.0
      expect(result[0]).to eq(0.0)
      expect(result[1]).to eq(50.0)
      expect(result[2]).to eq(50.0)
      expect(result[3]).to eq(100.0)
    end

    it "nilを含む場合はnilを保持し、非nil値のみでpercentileを算出する" do
      result = FinancialMetric.percentile_ranks([10, nil, 30, 20])
      expect(result[0]).to eq(0.0)
      expect(result[1]).to be_nil
      expect(result[2]).to eq(100.0)
      expect(result[3]).to eq(50.0)
    end

    it "全てnilの場合は全てnilを返す" do
      result = FinancialMetric.percentile_ranks([nil, nil, nil])
      expect(result).to eq([nil, nil, nil])
    end

    it "要素が1つの場合は50.0を返す" do
      result = FinancialMetric.percentile_ranks([42])
      expect(result).to eq([50.0])
    end

    it "空配列に対して空配列を返す" do
      result = FinancialMetric.percentile_ranks([])
      expect(result).to eq([])
    end

    it "全て同値の場合は全て同じpercentileを返す" do
      result = FinancialMetric.percentile_ranks([5, 5, 5])
      # rank 0,1,2の平均=1.0, n-1=2 → 1.0/2*100=50.0
      expect(result).to eq([50.0, 50.0, 50.0])
    end
  end

  describe ".get_growth_scores" do
    it "複数メトリクスに対して成長性スコアを算出する" do
      metrics = [
        FinancialMetric.new(id: 1, revenue_yoy: 0.2, operating_income_yoy: 0.3, eps_yoy: 0.15,
                            consecutive_revenue_growth: 3, consecutive_profit_growth: 2),
        FinancialMetric.new(id: 2, revenue_yoy: 0.05, operating_income_yoy: 0.1, eps_yoy: 0.05,
                            consecutive_revenue_growth: 1, consecutive_profit_growth: 0),
        FinancialMetric.new(id: 3, revenue_yoy: 0.1, operating_income_yoy: 0.2, eps_yoy: 0.1,
                            consecutive_revenue_growth: 2, consecutive_profit_growth: 1),
      ]

      result = FinancialMetric.get_growth_scores(metrics)

      expect(result.keys).to contain_exactly(1, 2, 3)
      # 全指標で最高のmetric 1が最高スコア
      expect(result[1]).to eq(100.0)
      # 全指標で最低のmetric 2が最低スコア
      expect(result[2]).to eq(0.0)
      # 中間のmetric 3
      expect(result[3]).to eq(50.0)
    end

    it "nil指標がある場合はウェイトを再配分する" do
      metrics = [
        FinancialMetric.new(id: 1, revenue_yoy: 0.2, operating_income_yoy: nil, eps_yoy: nil,
                            consecutive_revenue_growth: 3, consecutive_profit_growth: 2),
        FinancialMetric.new(id: 2, revenue_yoy: 0.05, operating_income_yoy: nil, eps_yoy: nil,
                            consecutive_revenue_growth: 1, consecutive_profit_growth: 1),
      ]

      result = FinancialMetric.get_growth_scores(metrics)

      # nil指標を除外してウェイト再配分されるので、有効な指標のみでスコアが決まる
      expect(result[1]).to eq(100.0)
      expect(result[2]).to eq(0.0)
    end

    it "空配列に対して空Hashを返す" do
      expect(FinancialMetric.get_growth_scores([])).to eq({})
    end
  end

  describe ".get_quality_scores" do
    it "複数メトリクスに対して質スコアを算出する" do
      metrics = [
        FinancialMetric.new(id: 1, roe: 0.15, operating_margin: 0.20, roa: 0.08,
                            operating_cf_positive: true, investing_cf_negative: true,
                            free_cf_positive: true),
        FinancialMetric.new(id: 2, roe: 0.05, operating_margin: 0.08, roa: 0.02,
                            operating_cf_positive: false, investing_cf_negative: false,
                            free_cf_positive: false),
        FinancialMetric.new(id: 3, roe: 0.10, operating_margin: 0.12, roa: 0.05,
                            operating_cf_positive: true, investing_cf_negative: false,
                            free_cf_positive: true),
      ]

      result = FinancialMetric.get_quality_scores(metrics)

      expect(result.keys).to contain_exactly(1, 2, 3)
      # 全指標で最高のmetric 1が最高スコア（boolean指標のtieにより厳密100にはならない）
      expect(result[1]).to be > result[3]
      expect(result[3]).to be > result[2]
      expect(result[2]).to eq(0.0)
    end

    it "CF指標がnilの場合はウェイトを再配分する" do
      metrics = [
        FinancialMetric.new(id: 1, roe: 0.15, operating_margin: 0.20, roa: 0.08,
                            operating_cf_positive: nil, investing_cf_negative: nil,
                            free_cf_positive: nil),
        FinancialMetric.new(id: 2, roe: 0.05, operating_margin: 0.08, roa: 0.02,
                            operating_cf_positive: nil, investing_cf_negative: nil,
                            free_cf_positive: nil),
      ]

      result = FinancialMetric.get_quality_scores(metrics)

      expect(result[1]).to eq(100.0)
      expect(result[2]).to eq(0.0)
    end
  end

  describe ".get_value_scores" do
    it "複数メトリクスに対して割安度スコアを算出する" do
      m1 = FinancialMetric.new(id: 1)
      m1.data_json = { "per" => 8.0, "pbr" => 0.8, "ev_ebitda" => 5.0, "dividend_yield" => 0.04 }
      m2 = FinancialMetric.new(id: 2)
      m2.data_json = { "per" => 25.0, "pbr" => 3.0, "ev_ebitda" => 15.0, "dividend_yield" => 0.01 }
      m3 = FinancialMetric.new(id: 3)
      m3.data_json = { "per" => 15.0, "pbr" => 1.5, "ev_ebitda" => 10.0, "dividend_yield" => 0.02 }

      result = FinancialMetric.get_value_scores([m1, m2, m3])

      # m1は低PER/PBR/EV_EBITDA + 高配当 → 最も割安
      expect(result[1]).to eq(100.0)
      # m2は高PER/PBR/EV_EBITDA + 低配当 → 最も割高
      expect(result[2]).to eq(0.0)
    end

    it "PERが0以下の場合はnilとして扱いウェイト再配分する" do
      m1 = FinancialMetric.new(id: 1)
      m1.data_json = { "per" => -5.0, "pbr" => 0.8, "ev_ebitda" => 5.0, "dividend_yield" => 0.03 }
      m2 = FinancialMetric.new(id: 2)
      m2.data_json = { "per" => -10.0, "pbr" => 2.0, "ev_ebitda" => 12.0, "dividend_yield" => 0.01 }

      result = FinancialMetric.get_value_scores([m1, m2])

      # PERは両方nil扱い、残りの指標でm1の方が割安
      expect(result[1]).to eq(100.0)
      expect(result[2]).to eq(0.0)
    end
  end

  describe ".get_composite_scores" do
    it "3つのサブスコアから総合スコアを算出する" do
      m1 = FinancialMetric.new(id: 1)
      m1.data_json = { "growth_score" => 80.0, "quality_score" => 90.0, "value_score" => 70.0 }
      m2 = FinancialMetric.new(id: 2)
      m2.data_json = { "growth_score" => 20.0, "quality_score" => 30.0, "value_score" => 40.0 }
      m3 = FinancialMetric.new(id: 3)
      m3.data_json = { "growth_score" => 50.0, "quality_score" => 60.0, "value_score" => 55.0 }

      result = FinancialMetric.get_composite_scores([m1, m2, m3])

      expect(result[1]).to eq(100.0)
      expect(result[2]).to eq(0.0)
      expect(result[3]).to eq(50.0)
    end

    it "一部のサブスコアがnilでもウェイト再配分して算出する" do
      m1 = FinancialMetric.new(id: 1)
      m1.data_json = { "growth_score" => 80.0, "quality_score" => 90.0, "value_score" => nil }
      m2 = FinancialMetric.new(id: 2)
      m2.data_json = { "growth_score" => 20.0, "quality_score" => 30.0, "value_score" => nil }

      result = FinancialMetric.get_composite_scores([m1, m2])

      expect(result[1]).to eq(100.0)
      expect(result[2]).to eq(0.0)
    end

    it "全サブスコアがnilの場合はnilを返す" do
      m1 = FinancialMetric.new(id: 1)
      m1.data_json = { "growth_score" => nil, "quality_score" => nil, "value_score" => nil }

      result = FinancialMetric.get_composite_scores([m1])

      expect(result[1]).to be_nil
    end
  end

  describe ".get_payout_ratio" do
    it "配当性向を算出する" do
      # DPS 50, EPS 200 → 25%
      expect(FinancialMetric.get_payout_ratio(50, 200)).to eq(25.0)
    end

    it "100%超の配当性向を記録する（タコ足配当）" do
      # DPS 150, EPS 100 → 150%
      expect(FinancialMetric.get_payout_ratio(150, 100)).to eq(150.0)
    end

    it "EPSがマイナスの場合はnilを返す" do
      expect(FinancialMetric.get_payout_ratio(50, -100)).to be_nil
    end

    it "EPSがゼロの場合はnilを返す" do
      expect(FinancialMetric.get_payout_ratio(50, 0)).to be_nil
    end

    it "DPSがnilの場合はnilを返す" do
      expect(FinancialMetric.get_payout_ratio(nil, 200)).to be_nil
    end

    it "EPSがnilの場合はnilを返す" do
      expect(FinancialMetric.get_payout_ratio(50, nil)).to be_nil
    end
  end

  describe ".get_consecutive_dividend_growth" do
    it "増配の場合は前期のカウントを引き継いで加算する" do
      prior_metric = FinancialMetric.new
      prior_metric.data_json = { "consecutive_dividend_growth" => 3 }

      result = FinancialMetric.get_consecutive_dividend_growth(60, 50, prior_metric)
      expect(result).to eq(4)
    end

    it "減配の場合は0にリセットする" do
      prior_metric = FinancialMetric.new
      prior_metric.data_json = { "consecutive_dividend_growth" => 5 }

      result = FinancialMetric.get_consecutive_dividend_growth(40, 50, prior_metric)
      expect(result).to eq(0)
    end

    it "配当据え置き（同額）の場合は0にリセットする" do
      prior_metric = FinancialMetric.new
      prior_metric.data_json = { "consecutive_dividend_growth" => 2 }

      result = FinancialMetric.get_consecutive_dividend_growth(50, 50, prior_metric)
      expect(result).to eq(0)
    end

    it "無配から有配への転換は増配開始（1）とする" do
      prior_metric = FinancialMetric.new
      prior_metric.data_json = { "consecutive_dividend_growth" => 0 }

      result = FinancialMetric.get_consecutive_dividend_growth(30, 0, prior_metric)
      expect(result).to eq(1)
    end

    it "前期メトリクスがnilの場合は初回増配（1）とする" do
      result = FinancialMetric.get_consecutive_dividend_growth(60, 50, nil)
      expect(result).to eq(1)
    end

    it "当期DPSがnilの場合はnilを返す" do
      expect(FinancialMetric.get_consecutive_dividend_growth(nil, 50, nil)).to be_nil
    end

    it "前期DPSがnilの場合はnilを返す" do
      expect(FinancialMetric.get_consecutive_dividend_growth(60, nil, nil)).to be_nil
    end
  end

  describe ".get_dividend_metrics" do
    it "正常ケース（DPS増加、EPSプラス）で全指標を算出する" do
      current_fv = FinancialValue.new(eps: BigDecimal("200"))
      allow(current_fv).to receive(:dividend_per_share_annual).and_return(BigDecimal("60"))

      prior_fv = FinancialValue.new
      allow(prior_fv).to receive(:dividend_per_share_annual).and_return(BigDecimal("50"))

      prior_metric = FinancialMetric.new
      prior_metric.data_json = { "consecutive_dividend_growth" => 2 }

      result = FinancialMetric.get_dividend_metrics(current_fv, prior_fv, prior_metric)

      expect(result["payout_ratio"]).to eq(30.0)
      expect(result["dividend_growth_rate"]).to eq(0.2)
      expect(result["consecutive_dividend_growth"]).to eq(3)
    end

    it "EPSマイナス時に配当性向がnilとなり結果から除外される" do
      current_fv = FinancialValue.new(eps: BigDecimal("-50"))
      allow(current_fv).to receive(:dividend_per_share_annual).and_return(BigDecimal("30"))

      prior_fv = FinancialValue.new
      allow(prior_fv).to receive(:dividend_per_share_annual).and_return(BigDecimal("25"))

      result = FinancialMetric.get_dividend_metrics(current_fv, prior_fv, nil)

      expect(result).not_to have_key("payout_ratio")
      expect(result["dividend_growth_rate"]).to eq(0.2)
      expect(result["consecutive_dividend_growth"]).to eq(1)
    end

    it "配当性向100%超（タコ足配当）を記録する" do
      current_fv = FinancialValue.new(eps: BigDecimal("30"))
      allow(current_fv).to receive(:dividend_per_share_annual).and_return(BigDecimal("50"))

      prior_fv = FinancialValue.new
      allow(prior_fv).to receive(:dividend_per_share_annual).and_return(BigDecimal("40"))

      result = FinancialMetric.get_dividend_metrics(current_fv, prior_fv, nil)

      expect(result["payout_ratio"]).to be_within(0.01).of(166.67)
    end

    it "無配から有配への転換で連続増配が1になる" do
      current_fv = FinancialValue.new(eps: BigDecimal("100"))
      allow(current_fv).to receive(:dividend_per_share_annual).and_return(BigDecimal("20"))

      prior_fv = FinancialValue.new
      allow(prior_fv).to receive(:dividend_per_share_annual).and_return(BigDecimal("0"))

      prior_metric = FinancialMetric.new
      prior_metric.data_json = { "consecutive_dividend_growth" => 0 }

      result = FinancialMetric.get_dividend_metrics(current_fv, prior_fv, prior_metric)

      expect(result["payout_ratio"]).to eq(20.0)
      expect(result["consecutive_dividend_growth"]).to eq(1)
    end

    it "前年データ欠損時は成長率・連続増配がnilとなり除外される" do
      current_fv = FinancialValue.new(eps: BigDecimal("100"))
      allow(current_fv).to receive(:dividend_per_share_annual).and_return(BigDecimal("30"))

      result = FinancialMetric.get_dividend_metrics(current_fv, nil, nil)

      expect(result["payout_ratio"]).to eq(30.0)
      expect(result).not_to have_key("dividend_growth_rate")
      expect(result).not_to have_key("consecutive_dividend_growth")
    end

    it "連続増配カウントのリセット（減配時）" do
      current_fv = FinancialValue.new(eps: BigDecimal("100"))
      allow(current_fv).to receive(:dividend_per_share_annual).and_return(BigDecimal("30"))

      prior_fv = FinancialValue.new
      allow(prior_fv).to receive(:dividend_per_share_annual).and_return(BigDecimal("40"))

      prior_metric = FinancialMetric.new
      prior_metric.data_json = { "consecutive_dividend_growth" => 5 }

      result = FinancialMetric.get_dividend_metrics(current_fv, prior_fv, prior_metric)

      expect(result["consecutive_dividend_growth"]).to eq(0)
      expect(result["dividend_growth_rate"]).to eq(-0.25)
    end
  end

  describe ".compute_weighted_scores" do
    it "全指標が同値の場合は全て同じスコアになる" do
      metrics = [
        FinancialMetric.new(id: 1, revenue_yoy: 0.1, operating_income_yoy: 0.1, eps_yoy: 0.1,
                            consecutive_revenue_growth: 1, consecutive_profit_growth: 1),
        FinancialMetric.new(id: 2, revenue_yoy: 0.1, operating_income_yoy: 0.1, eps_yoy: 0.1,
                            consecutive_revenue_growth: 1, consecutive_profit_growth: 1),
        FinancialMetric.new(id: 3, revenue_yoy: 0.1, operating_income_yoy: 0.1, eps_yoy: 0.1,
                            consecutive_revenue_growth: 1, consecutive_profit_growth: 1),
      ]

      result = FinancialMetric.get_growth_scores(metrics)

      expect(result[1]).to eq(result[2])
      expect(result[2]).to eq(result[3])
      expect(result[1]).to eq(50.0)
    end

    it "全指標がnilの場合はnilスコアを返す" do
      metrics = [
        FinancialMetric.new(id: 1, revenue_yoy: nil, operating_income_yoy: nil, eps_yoy: nil,
                            consecutive_revenue_growth: nil, consecutive_profit_growth: nil),
      ]

      result = FinancialMetric.get_growth_scores(metrics)

      expect(result[1]).to be_nil
    end
  end

  describe ".compute_cagr" do
    it "正常なCAGRを算出する" do
      # 100 -> 133.1 over 3 years: (133.1/100)^(1/3) - 1 ≈ 0.1
      result = FinancialMetric.compute_cagr(133.1, 100, 3)
      expect(result).to be_within(0.001).of(0.1)
    end

    it "5年CAGRを算出する" do
      # 100 -> 161.051 over 5 years: (161.051/100)^(1/5) - 1 ≈ 0.1
      result = FinancialMetric.compute_cagr(161.051, 100, 5)
      expect(result).to be_within(0.001).of(0.1)
    end

    it "成長なし（同一値）の場合はCAGR=0を返す" do
      result = FinancialMetric.compute_cagr(100, 100, 3)
      expect(result).to eq(0.0)
    end

    it "マイナス成長の場合は負のCAGRを返す" do
      # 100 -> 50 over 3 years
      result = FinancialMetric.compute_cagr(50, 100, 3)
      expect(result).to be < 0
    end

    it "開始値が0の場合はnilを返す" do
      expect(FinancialMetric.compute_cagr(100, 0, 3)).to be_nil
    end

    it "開始値が負の場合はnilを返す" do
      expect(FinancialMetric.compute_cagr(100, -50, 3)).to be_nil
    end

    it "終了値がnilの場合はnilを返す" do
      expect(FinancialMetric.compute_cagr(nil, 100, 3)).to be_nil
    end

    it "開始値がnilの場合はnilを返す" do
      expect(FinancialMetric.compute_cagr(100, nil, 3)).to be_nil
    end

    it "年数が0の場合はnilを返す" do
      expect(FinancialMetric.compute_cagr(100, 50, 0)).to be_nil
    end

    it "終了値が負で開始値が正の場合はnilを返す" do
      expect(FinancialMetric.compute_cagr(-50, 100, 3)).to be_nil
    end
  end

  describe ".get_cagr_metrics" do
    it "3年分・5年分のデータがある場合に全CAGRを算出する" do
      # 3年CAGR 10%: start * 1.1^3 = start * 1.331
      current_fv = FinancialValue.new(
        net_sales: 13310, operating_income: 2662, net_income: 1331, eps: BigDecimal("133.1"),
        fiscal_year_end: Date.new(2026, 3, 31),
      )

      fv_3y_ago = FinancialValue.new(
        net_sales: 10000, operating_income: 2000, net_income: 1000, eps: BigDecimal("100.0"),
        fiscal_year_end: Date.new(2023, 3, 31),
      )

      fv_5y_ago = FinancialValue.new(
        net_sales: 8000, operating_income: 1600, net_income: 800, eps: BigDecimal("80.0"),
        fiscal_year_end: Date.new(2021, 3, 31),
      )

      historical_fvs = [fv_3y_ago, fv_5y_ago]

      result = FinancialMetric.get_cagr_metrics(current_fv, historical_fvs)

      expect(result["revenue_cagr_3y"]).to be_within(0.002).of(0.1)
      expect(result["operating_income_cagr_3y"]).to be_within(0.002).of(0.1)
      expect(result["net_income_cagr_3y"]).to be_within(0.002).of(0.1)
      expect(result["eps_cagr_3y"]).to be_within(0.002).of(0.1)

      expect(result["revenue_cagr_5y"]).to be_a(Float)
      expect(result["operating_income_cagr_5y"]).to be_a(Float)
      expect(result["net_income_cagr_5y"]).to be_a(Float)
      expect(result["eps_cagr_5y"]).to be_a(Float)
    end

    it "データ不足（2年分しかない場合）に5年CAGRがnilであること" do
      current_fv = FinancialValue.new(
        net_sales: 1210, operating_income: 240,
        net_income: 180, eps: BigDecimal("66.0"),
        fiscal_year_end: Date.new(2026, 3, 31),
      )

      fv_2y_ago = FinancialValue.new(
        net_sales: 1000, operating_income: 200,
        net_income: 150, eps: BigDecimal("55.0"),
        fiscal_year_end: Date.new(2024, 3, 31),
      )

      historical_fvs = [fv_2y_ago]

      result = FinancialMetric.get_cagr_metrics(current_fv, historical_fvs)

      # 2年前のデータは3年CAGRの範囲外（±45日）なので該当なし
      expect(result).not_to have_key("revenue_cagr_3y")
      expect(result).not_to have_key("revenue_cagr_5y")
    end

    it "全期間同一値の場合にCAGR=0であること" do
      current_fv = FinancialValue.new(
        net_sales: 1000, operating_income: 200,
        net_income: 150, eps: BigDecimal("55.0"),
        fiscal_year_end: Date.new(2026, 3, 31),
      )

      fv_3y_ago = FinancialValue.new(
        net_sales: 1000, operating_income: 200,
        net_income: 150, eps: BigDecimal("55.0"),
        fiscal_year_end: Date.new(2023, 3, 31),
      )

      historical_fvs = [fv_3y_ago]

      result = FinancialMetric.get_cagr_metrics(current_fv, historical_fvs)

      expect(result["revenue_cagr_3y"]).to eq(0.0)
      expect(result["operating_income_cagr_3y"]).to eq(0.0)
      expect(result["net_income_cagr_3y"]).to eq(0.0)
      expect(result["eps_cagr_3y"]).to eq(0.0)
    end

    it "開始値が0の指標のみnilとなること" do
      current_fv = FinancialValue.new(
        net_sales: 1000, operating_income: 200,
        net_income: 150, eps: BigDecimal("55.0"),
        fiscal_year_end: Date.new(2026, 3, 31),
      )

      fv_3y_ago = FinancialValue.new(
        net_sales: 0, operating_income: 200,
        net_income: 150, eps: BigDecimal("55.0"),
        fiscal_year_end: Date.new(2023, 3, 31),
      )

      historical_fvs = [fv_3y_ago]

      result = FinancialMetric.get_cagr_metrics(current_fv, historical_fvs)

      expect(result).not_to have_key("revenue_cagr_3y")
      expect(result["operating_income_cagr_3y"]).to eq(0.0)
    end

    it "開始値が負の指標はnilとなること" do
      current_fv = FinancialValue.new(
        net_sales: 1000, operating_income: 200,
        net_income: 150, eps: BigDecimal("55.0"),
        fiscal_year_end: Date.new(2026, 3, 31),
      )

      fv_3y_ago = FinancialValue.new(
        net_sales: 1000, operating_income: -100,
        net_income: 150, eps: BigDecimal("55.0"),
        fiscal_year_end: Date.new(2023, 3, 31),
      )

      historical_fvs = [fv_3y_ago]

      result = FinancialMetric.get_cagr_metrics(current_fv, historical_fvs)

      expect(result["revenue_cagr_3y"]).to eq(0.0)
      expect(result).not_to have_key("operating_income_cagr_3y")
    end

    it "historical_fvsが空の場合は空Hashを返す" do
      current_fv = FinancialValue.new(
        net_sales: 1000, fiscal_year_end: Date.new(2026, 3, 31),
      )

      expect(FinancialMetric.get_cagr_metrics(current_fv, [])).to eq({})
    end
  end

  describe ".find_fv_for_period" do
    it "指定年数前のFinancialValueを返す" do
      current_fv = FinancialValue.new(fiscal_year_end: Date.new(2026, 3, 31))
      fv_3y = FinancialValue.new(fiscal_year_end: Date.new(2023, 3, 31))
      fv_5y = FinancialValue.new(fiscal_year_end: Date.new(2021, 3, 31))

      result = FinancialMetric.find_fv_for_period(current_fv, [fv_3y, fv_5y], 3)
      expect(result).to eq(fv_3y)

      result = FinancialMetric.find_fv_for_period(current_fv, [fv_3y, fv_5y], 5)
      expect(result).to eq(fv_5y)
    end

    it "±45日の範囲内であればマッチする" do
      current_fv = FinancialValue.new(fiscal_year_end: Date.new(2026, 3, 31))
      fv_shifted = FinancialValue.new(fiscal_year_end: Date.new(2023, 4, 15))

      result = FinancialMetric.find_fv_for_period(current_fv, [fv_shifted], 3)
      expect(result).to eq(fv_shifted)
    end

    it "±45日の範囲外であればnilを返す" do
      current_fv = FinancialValue.new(fiscal_year_end: Date.new(2026, 3, 31))
      fv_far = FinancialValue.new(fiscal_year_end: Date.new(2023, 6, 30))

      result = FinancialMetric.find_fv_for_period(current_fv, [fv_far], 3)
      expect(result).to be_nil
    end
  end

  describe ".get_cagr_acceleration" do
    it "CAGR加速度を算出する" do
      current_cagr = {
        "revenue_cagr_3y" => 0.15,
        "operating_income_cagr_3y" => 0.20,
        "net_income_cagr_3y" => 0.18,
        "eps_cagr_3y" => 0.17,
      }

      prior_metric = FinancialMetric.new
      prior_metric.data_json = {
        "revenue_cagr_3y" => 0.10,
        "operating_income_cagr_3y" => 0.12,
        "net_income_cagr_3y" => 0.11,
        "eps_cagr_3y" => 0.09,
      }

      result = FinancialMetric.get_cagr_acceleration(current_cagr, prior_metric)

      expect(result["cagr_acceleration_revenue"]).to be_within(0.0001).of(0.05)
      expect(result["cagr_acceleration_operating_income"]).to be_within(0.0001).of(0.08)
      expect(result["cagr_acceleration_net_income"]).to be_within(0.0001).of(0.07)
      expect(result["cagr_acceleration_eps"]).to be_within(0.0001).of(0.08)
    end

    it "prior_metricがnilの場合は空Hashを返す" do
      current_cagr = { "revenue_cagr_3y" => 0.15 }
      result = FinancialMetric.get_cagr_acceleration(current_cagr, nil)
      expect(result).to eq({})
    end

    it "当期のCAGRがnilの指標はスキップする" do
      current_cagr = {
        "revenue_cagr_3y" => 0.15,
      }

      prior_metric = FinancialMetric.new
      prior_metric.data_json = {
        "revenue_cagr_3y" => 0.10,
        "operating_income_cagr_3y" => 0.12,
      }

      result = FinancialMetric.get_cagr_acceleration(current_cagr, prior_metric)

      expect(result["cagr_acceleration_revenue"]).to be_within(0.0001).of(0.05)
      expect(result).not_to have_key("cagr_acceleration_operating_income")
    end

    it "前期のCAGRがnilの指標はスキップする" do
      current_cagr = {
        "revenue_cagr_3y" => 0.15,
        "operating_income_cagr_3y" => 0.20,
      }

      prior_metric = FinancialMetric.new
      prior_metric.data_json = {
        "revenue_cagr_3y" => 0.10,
      }

      result = FinancialMetric.get_cagr_acceleration(current_cagr, prior_metric)

      expect(result["cagr_acceleration_revenue"]).to be_within(0.0001).of(0.05)
      expect(result).not_to have_key("cagr_acceleration_operating_income")
    end
  end
end
