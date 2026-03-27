class DetectTrendTurningPointsJob < ApplicationJob
  # 転換点検出ジョブ
  #
  # 全上場企業の最新FinancialMetricについて転換点を検出し保存する。
  # CalculateFinancialMetricsJob とは独立して実行する。
  #
  # @param company_id [Integer, nil] 特定企業のみ実行する場合に指定
  #
  def perform(company_id: nil)
    @stats = { detected: 0, errors: 0 }
    @sector_stats_cache = {}

    scope = build_target_scope(company_id: company_id)

    scope.find_each do |metric|
      detect_for_metric(metric)
    end

    log_result
  end

  private

  def build_target_scope(company_id:)
    scope = FinancialMetric
      .consolidated
      .annual
      .latest_period
      .joins(:company)
      .merge(Company.listed)
      .includes(:company)

    scope = scope.where(company_id: company_id) if company_id
    scope
  end

  def detect_for_metric(metric)
    metric_history = load_metric_history(metric)
    sector_stats = load_sector_stats(metric.company)

    turning_points = TrendTurningPoint.detect_all(metric, metric_history, sector_stats: sector_stats)

    turning_points.each do |tp_attrs|
      TrendTurningPoint.find_or_create_by!(
        company_id: tp_attrs[:company_id],
        pattern_type: tp_attrs[:pattern_type],
        fiscal_year_end: tp_attrs[:fiscal_year_end],
        scope: tp_attrs[:scope],
        period_type: tp_attrs[:period_type],
      ) do |tp|
        tp.assign_attributes(tp_attrs)
      end
    end

    @stats[:detected] += turning_points.size
  rescue => e
    @stats[:errors] += 1
    Rails.logger.error(
      "[DetectTrendTurningPointsJob] Failed for metric##{metric.id} " \
      "(company=#{metric.company_id}): #{e.message}"
    )
  end

  # 過去3-5期分のFinancialMetricを取得（fiscal_year_end降順）
  def load_metric_history(metric)
    FinancialMetric
      .where(
        company_id: metric.company_id,
        scope: metric.scope,
        period_type: metric.period_type,
      )
      .where("fiscal_year_end < ?", metric.fiscal_year_end)
      .order(fiscal_year_end: :desc)
      .limit(5)
      .to_a
  end

  # セクター統計をキャッシュ付きで取得
  def load_sector_stats(company)
    sector_code = company.sector_33_code
    return nil if sector_code.blank?

    @sector_stats_cache[sector_code] ||= begin
      sector_metric = SectorMetric
        .where(classification: :sector_33, sector_code: sector_code)
        .order(calculated_on: :desc)
        .first
      sector_metric&.data_json
    end
  end

  def log_result
    Rails.logger.info(
      "[DetectTrendTurningPointsJob] Completed: " \
      "#{@stats[:detected]} detected, #{@stats[:errors]} errors"
    )
  end
end
