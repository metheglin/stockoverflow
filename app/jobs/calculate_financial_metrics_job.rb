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

    growth = FinancialMetric.get_growth_metrics(fv, previous_fv)
    profitability = FinancialMetric.get_profitability_metrics(fv)
    cf = FinancialMetric.get_cf_metrics(fv)
    consecutive = FinancialMetric.get_consecutive_metrics(growth, previous_metric)
    valuation = FinancialMetric.get_valuation_metrics(fv, load_stock_price(fv))

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

    if valuation.any?
      metric.data_json = (metric.data_json || {}).merge(valuation)
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

  def log_result
    Rails.logger.info(
      "[CalculateFinancialMetricsJob] Completed: " \
      "#{@stats[:calculated]} calculated, #{@stats[:errors]} errors"
    )
  end
end
