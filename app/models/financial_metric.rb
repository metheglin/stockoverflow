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
    revenue_surprise: { type: :decimal },
    operating_income_surprise: { type: :decimal },
    net_income_surprise: { type: :decimal },
    eps_surprise: { type: :decimal },
    # 財務健全性
    current_ratio: { type: :decimal },
    debt_to_equity: { type: :decimal },
    net_debt_to_equity: { type: :decimal },
    # 効率性
    asset_turnover: { type: :decimal },
    gross_margin: { type: :decimal },
    sga_ratio: { type: :decimal },
    # 四半期単独YoY
    standalone_quarter_revenue_yoy: { type: :decimal },
    standalone_quarter_operating_income_yoy: { type: :decimal },
    standalone_quarter_net_income_yoy: { type: :decimal },
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

  # 財務健全性指標を算出する
  #
  # @param fv [FinancialValue] 財務数値
  # @return [Hash] 財務健全性指標のHash（data_json格納用）
  #
  # 例:
  #   health = FinancialMetric.get_financial_health_metrics(fv)
  #   # => { "current_ratio" => 1.85, "debt_to_equity" => 0.75, "net_debt_to_equity" => 0.32 }
  #
  def self.get_financial_health_metrics(fv)
    result = {}

    current_assets = fv.current_assets
    current_liabilities = fv.current_liabilities
    noncurrent_liabilities = fv.noncurrent_liabilities
    shareholders_equity = fv.shareholders_equity

    # 流動比率
    if current_assets.present? && current_liabilities.present? && current_liabilities != 0
      result["current_ratio"] = (current_assets.to_d / current_liabilities.to_d).round(4).to_f
    end

    # 負債資本倍率
    if current_liabilities.present? && noncurrent_liabilities.present? && shareholders_equity.present? && shareholders_equity != 0
      total_debt = current_liabilities + noncurrent_liabilities
      result["debt_to_equity"] = (total_debt.to_d / shareholders_equity.to_d).round(4).to_f
    end

    # ネット負債資本倍率
    if fv.total_assets.present? && fv.net_assets.present? && fv.cash_and_equivalents.present? && shareholders_equity.present? && shareholders_equity != 0
      debt_approx = fv.total_assets - fv.net_assets
      net_debt = debt_approx - fv.cash_and_equivalents
      result["net_debt_to_equity"] = (net_debt.to_d / shareholders_equity.to_d).round(4).to_f
    end

    result
  end

  # 効率性指標を算出する
  #
  # @param fv [FinancialValue] 財務数値
  # @return [Hash] 効率性指標のHash（data_json格納用）
  #
  # 例:
  #   eff = FinancialMetric.get_efficiency_metrics(fv)
  #   # => { "asset_turnover" => 0.85, "gross_margin" => 0.45, "sga_ratio" => 0.30 }
  #
  def self.get_efficiency_metrics(fv)
    result = {}

    # 総資産回転率
    if fv.net_sales.present? && fv.total_assets.present? && fv.total_assets != 0
      result["asset_turnover"] = (fv.net_sales.to_d / fv.total_assets.to_d).round(4).to_f
    end

    # 売上総利益率
    gross_profit = fv.gross_profit
    if gross_profit.present? && fv.net_sales.present? && fv.net_sales != 0
      result["gross_margin"] = (gross_profit.to_d / fv.net_sales.to_d).round(4).to_f
    end

    # 販管費率
    sga = fv.sga_expenses
    if sga.present? && fv.net_sales.present? && fv.net_sales != 0
      result["sga_ratio"] = (sga.to_d / fv.net_sales.to_d).round(4).to_f
    end

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

  # EV/EBITDA を算出する
  #
  # EV (Enterprise Value) = 時価総額 + 有利子負債近似 - 現金同等物
  #   時価総額 = stock_price * shares_outstanding
  #   有利子負債近似 = total_assets - net_assets
  # EBITDA = 営業利益（減価償却費データ未取得のため簡易版）
  #
  # @param fv [FinancialValue] 財務数値
  # @param stock_price [Numeric, nil] 決算期末の株価
  # @return [Hash] EV/EBITDA指標のHash（data_json格納用）
  def self.get_ev_ebitda(fv, stock_price)
    return {} unless stock_price
    return {} unless fv.shares_outstanding.present?
    return {} unless fv.operating_income.present? && fv.operating_income != 0
    return {} unless fv.total_assets.present? && fv.net_assets.present?

    market_cap = stock_price * fv.shares_outstanding
    debt_approx = fv.total_assets - fv.net_assets
    cash = fv.cash_and_equivalents || 0

    ev = market_cap + debt_approx - cash
    ebitda = fv.operating_income

    { "ev_ebitda" => (ev.to_d / ebitda.to_d).round(2).to_f }
  end

  # 業績予想乖離率（Earning Surprise）を算出する
  #
  # 前期の業績予想と当期の実績を比較し、乖離率を算出する。
  # 乖離率 = (実績 - 予想) / |予想|
  #
  # @param current_fv [FinancialValue] 当期の財務数値（実績）
  # @param previous_fv [FinancialValue, nil] 前期の財務数値（予想を含む）
  # @return [Hash] 乖離率指標のHash（data_json格納用）
  #
  # 例:
  #   result = FinancialMetric.get_surprise_metrics(current_fv, previous_fv)
  #   # => { "revenue_surprise" => 0.05, "operating_income_surprise" => -0.1, ... }
  #
  def self.get_surprise_metrics(current_fv, previous_fv)
    return {} unless previous_fv
    return {} unless previous_fv.data_json.is_a?(Hash)

    result = {}

    forecast_pairs = {
      "revenue_surprise" => [:net_sales, "forecast_net_sales"],
      "operating_income_surprise" => [:operating_income, "forecast_operating_income"],
      "net_income_surprise" => [:net_income, "forecast_net_income"],
      "eps_surprise" => [:eps, "forecast_eps"],
    }

    forecast_pairs.each do |key, (actual_attr, forecast_key)|
      actual = current_fv.public_send(actual_attr)
      forecast = previous_fv.data_json[forecast_key]
      next if actual.nil? || forecast.nil? || forecast.to_d == 0

      surprise = ((actual.to_d - forecast.to_d) / forecast.to_d.abs).round(4).to_f
      result[key] = surprise
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

  # 四半期単独値を算出する
  #
  # 累計値から前四半期累計値を差し引き、当該四半期の単独値を算出する。
  # Q1の場合（prev_quarter_fv が nil）は累計値がそのまま単独値となる。
  #
  # @param fv [FinancialValue] 当該四半期の財務数値（累計）
  # @param prev_quarter_fv [FinancialValue, nil] 前四半期の財務数値（累計）
  # @param attr [Symbol] 属性名
  # @return [Numeric, nil] 単独四半期値
  def self.get_standalone_quarter_value(fv, prev_quarter_fv, attr)
    current_value = fv.public_send(attr)
    return nil if current_value.nil?

    return current_value if prev_quarter_fv.nil?

    prev_value = prev_quarter_fv.public_send(attr)
    return nil if prev_value.nil?

    current_value - prev_value
  end

  # 四半期前年同期比（単独四半期ベース）を算出する
  #
  # 累計値から単独四半期値を逆算し、前年同四半期との比較を行う。
  # annual期のデータには対応しない（空Hashを返す）。
  #
  # @param current_fv [FinancialValue] 当期四半期の財務数値（累計）
  # @param prior_same_quarter_fv [FinancialValue, nil] 前年同四半期の財務数値（累計）
  # @param current_prev_quarter_fv [FinancialValue, nil] 当期の前四半期財務数値（累計、Q1の場合nil）
  # @param prior_prev_quarter_fv [FinancialValue, nil] 前年の前四半期財務数値（累計、Q1の場合nil）
  # @return [Hash] 単独四半期YoY指標のHash（data_json格納用）
  #
  # 例:
  #   result = FinancialMetric.get_quarterly_yoy_metrics(q2_fv, prev_q2_fv,
  #     current_prev_quarter_fv: q1_fv, prior_prev_quarter_fv: prev_q1_fv)
  #   # => { "standalone_quarter_revenue_yoy" => 0.12, ... }
  #
  def self.get_quarterly_yoy_metrics(current_fv, prior_same_quarter_fv, current_prev_quarter_fv: nil, prior_prev_quarter_fv: nil)
    return {} unless prior_same_quarter_fv
    return {} if current_fv.annual?

    fields = {
      "standalone_quarter_revenue_yoy" => :net_sales,
      "standalone_quarter_operating_income_yoy" => :operating_income,
      "standalone_quarter_net_income_yoy" => :net_income,
    }

    result = {}

    fields.each do |metric_key, fv_attr|
      current_standalone = get_standalone_quarter_value(current_fv, current_prev_quarter_fv, fv_attr)
      prior_standalone = get_standalone_quarter_value(prior_same_quarter_fv, prior_prev_quarter_fv, fv_attr)

      yoy = compute_yoy(current_standalone, prior_standalone)
      result[metric_key] = yoy.to_f if yoy
    end

    result
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
