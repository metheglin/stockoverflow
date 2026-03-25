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
    # CAGR（年平均成長率）
    revenue_cagr_3y: { type: :decimal },
    revenue_cagr_5y: { type: :decimal },
    operating_income_cagr_3y: { type: :decimal },
    operating_income_cagr_5y: { type: :decimal },
    net_income_cagr_3y: { type: :decimal },
    net_income_cagr_5y: { type: :decimal },
    eps_cagr_3y: { type: :decimal },
    eps_cagr_5y: { type: :decimal },
    # CAGR加速度
    cagr_acceleration_revenue: { type: :decimal },
    cagr_acceleration_operating_income: { type: :decimal },
    cagr_acceleration_net_income: { type: :decimal },
    cagr_acceleration_eps: { type: :decimal },
    # 配当分析
    payout_ratio: { type: :decimal },
    dividend_growth_rate: { type: :decimal },
    consecutive_dividend_growth: { type: :integer },
    # 複合スコア
    growth_score: { type: :decimal },
    quality_score: { type: :decimal },
    value_score: { type: :decimal },
    composite_score: { type: :decimal },
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

  # 配当分析指標を算出する
  #
  # @param current_fv [FinancialValue] 当期の財務数値
  # @param prior_fv [FinancialValue, nil] 前期の財務数値
  # @param prior_metric [FinancialMetric, nil] 前期の指標
  # @return [Hash] 配当分析指標のHash（data_json格納用）
  #
  # 例:
  #   result = FinancialMetric.get_dividend_metrics(current_fv, prior_fv, prior_metric)
  #   # => { "payout_ratio" => 35.5, "dividend_growth_rate" => 0.1, "consecutive_dividend_growth" => 3 }
  #
  def self.get_dividend_metrics(current_fv, prior_fv, prior_metric)
    dps = current_fv.dividend_per_share_annual
    eps = current_fv.eps
    prior_dps = prior_fv&.dividend_per_share_annual

    result = {}
    result["payout_ratio"] = get_payout_ratio(dps, eps)
    result["dividend_growth_rate"] = compute_yoy(dps, prior_dps)&.to_f
    result["consecutive_dividend_growth"] = get_consecutive_dividend_growth(dps, prior_dps, prior_metric)
    result.compact
  end

  # 配当性向を算出する
  #
  # @param dps [Numeric, nil] 1株あたり配当金
  # @param eps [Numeric, nil] 1株あたり利益
  # @return [Float, nil] 配当性向（%）。EPSがマイナスまたはゼロの場合nil
  def self.get_payout_ratio(dps, eps)
    return nil if dps.nil? || eps.nil?
    return nil if eps.to_d <= 0

    (dps.to_d / eps.to_d * 100).round(2).to_f
  end

  # 連続増配期間を算出する
  #
  # @param dps [Numeric, nil] 当期DPS
  # @param prior_dps [Numeric, nil] 前期DPS
  # @param prior_metric [FinancialMetric, nil] 前期の指標
  # @return [Integer, nil] 連続増配期間。判定不能な場合nil
  def self.get_consecutive_dividend_growth(dps, prior_dps, prior_metric)
    return nil if dps.nil? || prior_dps.nil?

    if dps.to_d > prior_dps.to_d
      prev_count = prior_metric&.consecutive_dividend_growth || 0
      prev_count + 1
    else
      0
    end
  end

  # CAGR計算対象の指標定義
  # key: data_jsonに格納するときのprefix, value: FinancialValueの属性名
  CAGR_TARGETS = {
    revenue: :net_sales,
    operating_income: :operating_income,
    net_income: :net_income,
    eps: :eps,
  }.freeze

  # CAGR計算対象の年数
  CAGR_PERIODS = [3, 5].freeze

  # CAGR（年平均成長率）を算出する
  #
  # CAGR = (終了値 / 開始値)^(1/年数) - 1
  # 開始値が0以下の場合はnilを返す（対数計算不可）
  #
  # @param end_value [Numeric, nil] 終了時点の値
  # @param start_value [Numeric, nil] 開始時点の値
  # @param years [Integer] 年数
  # @return [Float, nil] CAGR（小数表現）
  def self.compute_cagr(end_value, start_value, years)
    return nil if end_value.nil? || start_value.nil?
    return nil if start_value.to_d <= 0
    return nil if years <= 0

    ratio = end_value.to_d / start_value.to_d
    return nil if ratio < 0

    (ratio.to_f ** (1.0 / years) - 1.0).round(4)
  end

  # 複数年のCAGRメトリクスを一括算出する
  #
  # @param current_fv [FinancialValue] 当期の財務数値
  # @param historical_fvs [Array<FinancialValue>] 過去のFinancialValueの配列（fiscal_year_end降順）
  #   同一company_id・同一scope・同一period_typeであること
  # @return [Hash] CAGRメトリクスのHash（data_json格納用）
  #
  # 例:
  #   result = FinancialMetric.get_cagr_metrics(current_fv, historical_fvs)
  #   # => { "revenue_cagr_3y" => 0.15, "revenue_cagr_5y" => 0.12, ... }
  #
  def self.get_cagr_metrics(current_fv, historical_fvs)
    return {} if historical_fvs.blank?

    # fiscal_year_endの降順ソート済みを前提に、年数差を計算
    result = {}

    CAGR_TARGETS.each do |prefix, attr|
      end_value = current_fv.public_send(attr)
      next if end_value.nil?

      CAGR_PERIODS.each do |period|
        start_fv = find_fv_for_period(current_fv, historical_fvs, period)
        next unless start_fv

        start_value = start_fv.public_send(attr)
        cagr = compute_cagr(end_value, start_value, period)
        result["#{prefix}_cagr_#{period}y"] = cagr unless cagr.nil?
      end
    end

    result
  end

  # CAGR加速度を算出する
  #
  # 直近3年CAGRと、3年前時点での3年CAGRを比較して加速度を算出する。
  # cagr_acceleration = current_3y_cagr - prior_3y_cagr
  #
  # @param current_cagr_metrics [Hash] 当期のCAGRメトリクス（get_cagr_metricsの結果）
  # @param prior_metric [FinancialMetric, nil] 3年前のFinancialMetric
  # @return [Hash] CAGR加速度のHash（data_json格納用）
  #
  # 例:
  #   result = FinancialMetric.get_cagr_acceleration(cagr_metrics, prior_metric)
  #   # => { "cagr_acceleration_revenue" => 0.05, ... }
  #
  def self.get_cagr_acceleration(current_cagr_metrics, prior_metric)
    return {} unless prior_metric

    result = {}

    CAGR_TARGETS.each_key do |prefix|
      current_cagr = current_cagr_metrics["#{prefix}_cagr_3y"]
      prior_cagr = prior_metric.public_send(:"#{prefix}_cagr_3y")
      next if current_cagr.nil? || prior_cagr.nil?

      result["cagr_acceleration_#{prefix}"] = (current_cagr - prior_cagr.to_f).round(4)
    end

    result
  end

  # historical_fvsからN年前のFinancialValueを検索する
  #
  # @param current_fv [FinancialValue] 基準となる当期のFinancialValue
  # @param historical_fvs [Array<FinancialValue>] 過去のFinancialValueの配列
  # @param years [Integer] 遡る年数
  # @return [FinancialValue, nil]
  def self.find_fv_for_period(current_fv, historical_fvs, years)
    target_date = current_fv.fiscal_year_end - years.years

    historical_fvs.find do |fv|
      (fv.fiscal_year_end - target_date).abs <= 45
    end
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

  # スコア計算用の重み定数
  GROWTH_SCORE_WEIGHTS = {
    revenue_yoy: 0.25,
    operating_income_yoy: 0.25,
    eps_yoy: 0.20,
    consecutive_revenue_growth: 0.15,
    consecutive_profit_growth: 0.15,
  }.freeze

  QUALITY_SCORE_WEIGHTS = {
    roe: 0.25,
    operating_margin: 0.25,
    cf_health: 0.20,
    free_cf_positive: 0.15,
    roa: 0.15,
  }.freeze

  VALUE_SCORE_WEIGHTS = {
    per_inverse: 0.30,
    pbr_inverse: 0.30,
    ev_ebitda_inverse: 0.20,
    dividend_yield: 0.20,
  }.freeze

  COMPOSITE_SCORE_WEIGHTS = {
    growth_score: 0.35,
    quality_score: 0.40,
    value_score: 0.25,
  }.freeze

  # 値の配列からpercentile rankを算出する
  #
  # 各値について全体中の相対位置を 0〜100 で返す。
  # 同値はすべて同じpercentile（平均順位ベース）となる。
  # nil は結果でも nil として保持される。
  #
  # @param values [Array<Numeric, nil>] 値の配列
  # @return [Array<Float, nil>] percentile rank（0〜100）の配列
  #
  # 例:
  #   percentile_ranks([10, 20, 30, 40, 50])
  #   # => [0.0, 25.0, 50.0, 75.0, 100.0]
  #
  def self.percentile_ranks(values)
    non_nil_values = values.each_with_index.reject { |v, _| v.nil? }.map { |v, i| [v.to_f, i] }
    return values.map { nil } if non_nil_values.empty?

    result = Array.new(values.size)

    if non_nil_values.size == 1
      result[non_nil_values.first[1]] = 50.0
      return result
    end

    sorted = non_nil_values.sort_by { |v, _| v }
    n = sorted.size

    # 同値をグループ化して平均順位を割り当て
    rank_map = {}
    i = 0
    while i < n
      j = i
      j += 1 while j < n && sorted[j][0] == sorted[i][0]
      avg_rank = (i...j).sum.to_f / (j - i)
      (i...j).each { |k| rank_map[sorted[k][1]] = avg_rank }
      i = j
    end

    rank_map.each do |original_index, rank|
      result[original_index] = (rank / (n - 1).to_f * 100.0).round(2)
    end

    result
  end

  # Growth Score（成長性スコア）を算出する
  #
  # 全企業の FinancialMetric をバッチで受け取り、percentile rank ベースで
  # 各指標を 0〜100 に正規化し、重み付き加重平均でスコアを算出する。
  #
  # @param metrics [Array<FinancialMetric>] 対象メトリクス群
  # @return [Hash{Integer => Float}] metric.id => score のHash
  #
  def self.get_growth_scores(metrics)
    compute_weighted_scores(metrics, GROWTH_SCORE_WEIGHTS) do |metric, key|
      case key
      when :revenue_yoy then metric.revenue_yoy&.to_f
      when :operating_income_yoy then metric.operating_income_yoy&.to_f
      when :eps_yoy then metric.eps_yoy&.to_f
      when :consecutive_revenue_growth then metric.consecutive_revenue_growth&.to_f
      when :consecutive_profit_growth then metric.consecutive_profit_growth&.to_f
      end
    end
  end

  # Quality Score（質スコア）を算出する
  #
  # @param metrics [Array<FinancialMetric>] 対象メトリクス群
  # @return [Hash{Integer => Float}] metric.id => score のHash
  #
  def self.get_quality_scores(metrics)
    compute_weighted_scores(metrics, QUALITY_SCORE_WEIGHTS) do |metric, key|
      case key
      when :roe then metric.roe&.to_f
      when :operating_margin then metric.operating_margin&.to_f
      when :cf_health
        op = metric.operating_cf_positive
        inv = metric.investing_cf_negative
        (op.nil? || inv.nil?) ? nil : ((op ? 1.0 : 0.0) + (inv ? 1.0 : 0.0))
      when :free_cf_positive
        metric.free_cf_positive.nil? ? nil : (metric.free_cf_positive ? 1.0 : 0.0)
      when :roa then metric.roa&.to_f
      end
    end
  end

  # Value Score（割安度スコア）を算出する
  #
  # PER/PBR/EV_EBITDA は低いほど割安なので逆数にしてからpercentile化する。
  #
  # @param metrics [Array<FinancialMetric>] 対象メトリクス群
  # @return [Hash{Integer => Float}] metric.id => score のHash
  #
  def self.get_value_scores(metrics)
    compute_weighted_scores(metrics, VALUE_SCORE_WEIGHTS) do |metric, key|
      case key
      when :per_inverse
        per = metric.per&.to_f
        (per.nil? || per <= 0) ? nil : (1.0 / per)
      when :pbr_inverse
        pbr = metric.pbr&.to_f
        (pbr.nil? || pbr <= 0) ? nil : (1.0 / pbr)
      when :ev_ebitda_inverse
        ev = metric.ev_ebitda&.to_f
        (ev.nil? || ev <= 0) ? nil : (1.0 / ev)
      when :dividend_yield
        metric.dividend_yield&.to_f
      end
    end
  end

  # Composite Score（総合スコア）を算出する
  #
  # Growth/Quality/Value の各スコアが data_json に格納済みであることを前提とする。
  #
  # @param metrics [Array<FinancialMetric>] 対象メトリクス群（スコア格納済み）
  # @return [Hash{Integer => Float}] metric.id => score のHash
  #
  def self.get_composite_scores(metrics)
    compute_weighted_scores(metrics, COMPOSITE_SCORE_WEIGHTS) do |metric, key|
      case key
      when :growth_score then metric.growth_score&.to_f
      when :quality_score then metric.quality_score&.to_f
      when :value_score then metric.value_score&.to_f
      end
    end
  end

  # 重み付きpercentileスコアを汎用的に算出する
  #
  # @param metrics [Array<FinancialMetric>] 対象メトリクス群
  # @param weights [Hash{Symbol => Float}] 指標名と重みのHash
  # @yield [metric, key] 各指標の値を返すブロック
  # @return [Hash{Integer => Float}] metric.id => score のHash
  #
  def self.compute_weighted_scores(metrics, weights, &value_extractor)
    return {} if metrics.empty?

    # 各指標のpercentile rankを算出
    percentile_data = {}
    weights.each_key do |key|
      raw_values = metrics.map { |m| value_extractor.call(m, key) }
      percentile_data[key] = percentile_ranks(raw_values)
    end

    # 各メトリクスについて加重平均スコアを算出
    result = {}
    metrics.each_with_index do |metric, idx|
      total_weight = 0.0
      weighted_sum = 0.0

      weights.each do |key, weight|
        pct = percentile_data[key][idx]
        next if pct.nil?
        weighted_sum += pct * weight
        total_weight += weight
      end

      result[metric.id] = total_weight > 0 ? (weighted_sum / total_weight).round(2) : nil
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
