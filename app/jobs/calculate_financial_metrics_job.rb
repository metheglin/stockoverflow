class CalculateFinancialMetricsJob < ApplicationJob
  # 指標算出ジョブ
  #
  # @param recalculate [Boolean] trueの場合全レコードを再計算
  # @param company_id [Integer, nil] 特定企業のみ算出する場合に指定
  #
  def perform(recalculate: false, company_id: nil)
    @stats = { calculated: 0, errors: 0 }

    target_values = build_target_scope(recalculate: recalculate, company_id: company_id)

    target_values.find_each do |fv|
      calculate_metrics_for(fv)
    end

    calculate_scores(company_id: company_id)

    log_result
  end

  private

  # 算出対象の FinancialValue スコープを構築
  def build_target_scope(recalculate:, company_id:)
    scope = FinancialValue.all
    scope = scope.where(company_id: company_id) if company_id

    if recalculate
      scope
    else
      scope.left_joins(:financial_metric)
           .where(
             "financial_metrics.id IS NULL OR financial_values.updated_at > financial_metrics.updated_at"
           )
    end
  end

  # 1つの FinancialValue に対して指標を算出
  def calculate_metrics_for(fv)
    previous_fv = find_previous_financial_value(fv)
    previous_metric = previous_fv ? find_metric(previous_fv) : nil

    stock_price = load_stock_price(fv)

    growth = FinancialMetric.get_growth_metrics(fv, previous_fv)
    profitability = FinancialMetric.get_profitability_metrics(fv)
    cf = FinancialMetric.get_cf_metrics(fv)
    consecutive = FinancialMetric.get_consecutive_metrics(growth, previous_metric)
    valuation = FinancialMetric.get_valuation_metrics(fv, stock_price)
    ev_ebitda = FinancialMetric.get_ev_ebitda(fv, stock_price)
    surprise = FinancialMetric.get_surprise_metrics(fv, previous_fv)
    financial_health = FinancialMetric.get_financial_health_metrics(fv)
    efficiency = FinancialMetric.get_efficiency_metrics(fv)
    dividend = FinancialMetric.get_dividend_metrics(fv, previous_fv, previous_metric)

    quarterly_yoy = {}
    unless fv.annual?
      current_prev_quarter_fv = find_previous_quarter_financial_value(fv)
      prior_prev_quarter_fv = previous_fv ? find_previous_quarter_financial_value(previous_fv) : nil
      quarterly_yoy = FinancialMetric.get_quarterly_yoy_metrics(
        fv, previous_fv,
        current_prev_quarter_fv: current_prev_quarter_fv,
        prior_prev_quarter_fv: prior_prev_quarter_fv,
      )
    end

    metric = FinancialMetric.find_or_initialize_by(
      company_id: fv.company_id,
      fiscal_year_end: fv.fiscal_year_end,
      scope: fv.scope,
      period_type: fv.period_type,
    )

    metric.assign_attributes(
      financial_value: fv,
      **growth,
      **profitability,
      **cf,
      **consecutive,
    )

    json_updates = {}.merge(valuation).merge(ev_ebitda).merge(surprise).merge(financial_health).merge(efficiency).merge(dividend).merge(quarterly_yoy)
    if json_updates.any?
      metric.data_json = (metric.data_json || {}).merge(json_updates)
    end

    metric.save! if metric.new_record? || metric.changed?
    @stats[:calculated] += 1
  rescue => e
    @stats[:errors] += 1
    Rails.logger.error(
      "[CalculateFinancialMetricsJob] Failed for FV##{fv.id} " \
      "(company=#{fv.company_id}, fy=#{fv.fiscal_year_end}): #{e.message}"
    )
  end

  # 前期の FinancialValue を検索
  # fiscal_year_end の約1年前（±1ヶ月）の範囲で検索
  def find_previous_financial_value(fv)
    prev_start = fv.fiscal_year_end - 13.months
    prev_end = fv.fiscal_year_end - 11.months

    FinancialValue
      .where(
        company_id: fv.company_id,
        scope: fv.scope,
        period_type: fv.period_type,
        fiscal_year_end: prev_start..prev_end,
      )
      .order(fiscal_year_end: :desc)
      .first
  end

  # 同一会計年度内の前四半期 FinancialValue を検索
  # Q2 → Q1、Q3 → Q2 を返す。Q1・annual の場合は nil
  def find_previous_quarter_financial_value(fv)
    prior_period = { "q2" => "q1", "q3" => "q2" }[fv.period_type]
    return nil unless prior_period

    FinancialValue.find_by(
      company_id: fv.company_id,
      scope: fv.scope,
      fiscal_year_end: fv.fiscal_year_end,
      period_type: prior_period,
    )
  end

  # FinancialValue に対応する FinancialMetric を検索
  def find_metric(fv)
    FinancialMetric.find_by(
      company_id: fv.company_id,
      fiscal_year_end: fv.fiscal_year_end,
      scope: fv.scope,
      period_type: fv.period_type,
    )
  end

  # 決算期末日に最も近い株価（終値）を取得
  # fiscal_year_end の前後7日の範囲で検索し、最も近い日の調整後終値を返す
  def load_stock_price(fv)
    DailyQuote
      .where(company_id: fv.company_id)
      .where(traded_on: (fv.fiscal_year_end - 7.days)..(fv.fiscal_year_end + 7.days))
      .order(Arel.sql("ABS(JULIANDAY(traded_on) - JULIANDAY('#{fv.fiscal_year_end}'))"))
      .pick(:adjusted_close)
  end

  # 全企業分のスコアをバッチで算出し data_json に格納する
  #
  # percentile rank は同一 fiscal_year_end + period_type + scope の母集団で算出する。
  # company_id 指定時もスコア計算は全企業を母集団として再計算する。
  def calculate_scores(company_id: nil)
    FinancialMetric
      .select(:fiscal_year_end, :period_type, :scope)
      .distinct
      .each do |group|
        metrics = FinancialMetric
          .where(
            fiscal_year_end: group.fiscal_year_end,
            period_type: group.period_type,
            scope: group.scope,
          )
          .to_a

        next if metrics.empty?

        growth_scores = FinancialMetric.get_growth_scores(metrics)
        quality_scores = FinancialMetric.get_quality_scores(metrics)
        value_scores = FinancialMetric.get_value_scores(metrics)

        # growth/quality/value を各 metric の data_json に反映
        metrics.each do |metric|
          json = (metric.data_json || {}).dup
          json["growth_score"] = growth_scores[metric.id]
          json["quality_score"] = quality_scores[metric.id]
          json["value_score"] = value_scores[metric.id]
          metric.data_json = json
        end

        # composite score は growth/quality/value が格納済みの状態で算出
        composite_scores = FinancialMetric.get_composite_scores(metrics)

        metrics.each do |metric|
          json = (metric.data_json || {}).dup
          json["composite_score"] = composite_scores[metric.id]
          metric.data_json = json
          metric.save! if metric.changed?
        end
      end
  rescue => e
    Rails.logger.error(
      "[CalculateFinancialMetricsJob] Score calculation failed: #{e.message}"
    )
  end

  def log_result
    Rails.logger.info(
      "[CalculateFinancialMetricsJob] Completed: " \
      "#{@stats[:calculated]} calculated, #{@stats[:errors]} errors"
    )
  end
end
