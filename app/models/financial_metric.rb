class FinancialMetric < ApplicationRecord
  include JsonAttribute

  belongs_to :company
  belongs_to :financial_value

  enum :scope, {
    consolidated: 0,
    non_consolidated: 1,
  }

  enum :period_type, {
    annual: 0,
    q1: 1,
    q2: 2,
    q3: 3,
  }

  define_json_attributes :data_json, schema: {
    per: { type: :decimal },
    pbr: { type: :decimal },
    psr: { type: :decimal },
    dividend_yield: { type: :decimal },
    ev_ebitda: { type: :decimal },
  }

  # 2つの FinancialValue から成長性指標（YoY）を算出する
  #
  # @param current_fv [FinancialValue] 当期の財務数値
  # @param previous_fv [FinancialValue, nil] 前期の財務数値
  # @return [Hash] YoY指標のHash
  #
  # 例:
  #   yoy = FinancialMetric.get_growth_metrics(current_fv, previous_fv)
  #   # => { revenue_yoy: 0.15, operating_income_yoy: 0.20, ... }
  #
  def self.get_growth_metrics(current_fv, previous_fv)
    return {} unless previous_fv

    {
      revenue_yoy: compute_yoy(current_fv.net_sales, previous_fv.net_sales),
      operating_income_yoy: compute_yoy(current_fv.operating_income, previous_fv.operating_income),
      ordinary_income_yoy: compute_yoy(current_fv.ordinary_income, previous_fv.ordinary_income),
      net_income_yoy: compute_yoy(current_fv.net_income, previous_fv.net_income),
      eps_yoy: compute_yoy(current_fv.eps, previous_fv.eps),
    }
  end

  # FinancialValue から収益性指標を算出する
  #
  # @param fv [FinancialValue] 財務数値
  # @return [Hash] 収益性指標のHash
  def self.get_profitability_metrics(fv)
    {
      roe: safe_divide(fv.net_income, fv.net_assets),
      roa: safe_divide(fv.net_income, fv.total_assets),
      operating_margin: safe_divide(fv.operating_income, fv.net_sales),
      ordinary_margin: safe_divide(fv.ordinary_income, fv.net_sales),
      net_margin: safe_divide(fv.net_income, fv.net_sales),
    }
  end

  # FinancialValue から CF指標を算出する
  #
  # @param fv [FinancialValue] 財務数値
  # @return [Hash] CF指標のHash
  def self.get_cf_metrics(fv)
    result = {}

    if fv.operating_cf.present? && fv.investing_cf.present?
      free_cf = fv.operating_cf + fv.investing_cf
      result[:free_cf] = free_cf
      result[:free_cf_positive] = free_cf > 0
    end

    result[:operating_cf_positive] = fv.operating_cf > 0 if fv.operating_cf.present?
    result[:investing_cf_negative] = fv.investing_cf < 0 if fv.investing_cf.present?

    result
  end

  # 連続増収増益期数を算出する
  #
  # @param growth_metrics [Hash] get_growth_metricsの結果
  # @param previous_metric [FinancialMetric, nil] 前期の指標
  # @return [Hash] 連続指標のHash
  def self.get_consecutive_metrics(growth_metrics, previous_metric)
    prev_revenue = previous_metric&.consecutive_revenue_growth || 0
    prev_profit = previous_metric&.consecutive_profit_growth || 0

    {
      consecutive_revenue_growth:
        growth_metrics[:revenue_yoy].present? && growth_metrics[:revenue_yoy] > 0 ?
          prev_revenue + 1 : 0,
      consecutive_profit_growth:
        growth_metrics[:net_income_yoy].present? && growth_metrics[:net_income_yoy] > 0 ?
          prev_profit + 1 : 0,
    }
  end

  # バリュエーション指標を算出する
  #
  # @param fv [FinancialValue] 財務数値
  # @param stock_price [Numeric, nil] 決算期末の株価
  # @return [Hash] バリュエーション指標のHash（data_json格納用）
  def self.get_valuation_metrics(fv, stock_price)
    return {} unless stock_price

    result = {}
    result["per"] = safe_divide(stock_price, fv.eps)&.to_f if fv.eps.present?
    result["pbr"] = safe_divide(stock_price, fv.bps)&.to_f if fv.bps.present?

    if fv.shares_outstanding.present? && fv.net_sales.present? && fv.net_sales > 0
      market_cap = stock_price * fv.shares_outstanding
      result["psr"] = (market_cap.to_d / fv.net_sales).to_f
    end

    if fv.data_json&.dig("dividend_per_share_annual").present? && stock_price > 0
      dividend = fv.data_json["dividend_per_share_annual"].to_f
      result["dividend_yield"] = (dividend / stock_price).to_f
    end

    result
  end

  # 連続増収増益期数の整合性を検証する
  #
  # @param metrics [Array<Hash>] fiscal_year_end昇順にソートされた指標のArray
  #   各要素は :revenue_yoy, :net_income_yoy, :consecutive_revenue_growth,
  #   :consecutive_profit_growth, :fiscal_year_end を含む
  # @return [Array<Hash>] 不整合のあるエントリのArray
  #   各要素: { fiscal_year_end:, field:, expected:, actual: }
  #
  # 例:
  #   metrics = [
  #     { fiscal_year_end: "2024-03-31", revenue_yoy: 0.1, consecutive_revenue_growth: 1, ... },
  #     { fiscal_year_end: "2025-03-31", revenue_yoy: 0.05, consecutive_revenue_growth: 2, ... },
  #   ]
  #   FinancialMetric.detect_consecutive_anomalies(metrics)
  #   # => [] (整合性OK)
  #
  def self.detect_consecutive_anomalies(metrics)
    anomalies = []

    metrics.each_cons(2) do |prev, current|
      expected_revenue = get_expected_consecutive(
        prev[:consecutive_revenue_growth], current[:revenue_yoy]
      )
      if current[:consecutive_revenue_growth] != expected_revenue
        anomalies << {
          fiscal_year_end: current[:fiscal_year_end],
          field: :consecutive_revenue_growth,
          expected: expected_revenue,
          actual: current[:consecutive_revenue_growth],
        }
      end

      expected_profit = get_expected_consecutive(
        prev[:consecutive_profit_growth], current[:net_income_yoy]
      )
      if current[:consecutive_profit_growth] != expected_profit
        anomalies << {
          fiscal_year_end: current[:fiscal_year_end],
          field: :consecutive_profit_growth,
          expected: expected_profit,
          actual: current[:consecutive_profit_growth],
        }
      end
    end

    anomalies
  end

  # 前期の連続期数とYoYから期待される連続期数を算出する
  #
  # @param previous_count [Integer] 前期の連続期数
  # @param yoy [BigDecimal, nil] 当期のYoY
  # @return [Integer] 期待される連続期数
  def self.get_expected_consecutive(previous_count, yoy)
    if yoy.present? && yoy > 0
      previous_count + 1
    else
      0
    end
  end

  # YoY（前年同期比）を算出する
  #
  # @param current [Numeric, nil] 当期の値
  # @param previous [Numeric, nil] 前期の値
  # @return [BigDecimal, nil] YoY比率（小数表現）
  def self.compute_yoy(current, previous)
    return nil if current.nil? || previous.nil? || previous == 0

    ((current.to_d - previous.to_d) / previous.to_d.abs).round(4)
  end

  # 安全な除算（分母が0またはnilの場合はnilを返す）
  #
  # @param numerator [Numeric, nil]
  # @param denominator [Numeric, nil]
  # @return [BigDecimal, nil]
  def self.safe_divide(numerator, denominator)
    return nil if numerator.nil? || denominator.nil? || denominator == 0

    (numerator.to_d / denominator.to_d).round(4)
  end
end
