class CalculateSectorMetricsJob < ApplicationJob
  # セクター別統計量を算出し sector_metrics に保存する
  #
  # @param classification [String] "sector_17" or "sector_33"。未指定の場合は両方
  # @param calculated_on [Date] スナップショット日付。デフォルトは当日
  #
  def perform(classification: nil, calculated_on: Date.current)
    @calculated_on = calculated_on
    @stats = { created: 0, updated: 0, errors: 0 }

    # 最新の連結・通期 FinancialMetric を企業ごとに1件ずつ取得
    @latest_metrics = load_latest_metrics

    if classification.nil? || classification == "sector_33"
      calculate_for_classification(:sector_33)
    end
    if classification.nil? || classification == "sector_17"
      calculate_for_classification(:sector_17)
    end

    # パーセンタイルランキング算出（セクター統計算出後に実行）
    calculate_percentiles

    log_result
  end

  private

  # 全上場企業の最新 連結・通期 FinancialMetric を取得
  #
  # includes(:company) で company の sector 情報を参照可能にする
  def load_latest_metrics
    FinancialMetric
      .consolidated
      .annual
      .where(
        "fiscal_year_end = (SELECT MAX(fm2.fiscal_year_end) FROM financial_metrics fm2 " \
        "WHERE fm2.company_id = financial_metrics.company_id " \
        "AND fm2.scope = financial_metrics.scope " \
        "AND fm2.period_type = financial_metrics.period_type)"
      )
      .includes(:company)
      .where(company_id: Company.listed.select(:id))
      .to_a
  end

  # 指定分類でセクター統計を算出・保存
  def calculate_for_classification(classification)
    sector_attr = classification == :sector_33 ? :sector_33_code : :sector_17_code
    name_attr = classification == :sector_33 ? :sector_33_name : :sector_17_name

    grouped = @latest_metrics.group_by { |m| m.company.public_send(sector_attr) }

    grouped.each do |sector_code, metrics|
      next if sector_code.blank?

      sector_name = metrics.first.company.public_send(name_attr) || sector_code
      calculate_sector(classification, sector_code, sector_name, metrics)
    end
  end

  # 1セクター分の統計を算出・保存
  def calculate_sector(classification, sector_code, sector_name, metrics)
    data_json = {}

    SectorMetric::METRIC_KEYS.each do |metric_key|
      values = metrics.map { |m| SectorMetric.get_metric_value(m, metric_key) }
      stats = SectorMetric.get_statistics(values)
      data_json[metric_key.to_s] = stats if stats
    end

    record = SectorMetric.find_or_initialize_by(
      classification: classification,
      sector_code: sector_code,
      calculated_on: @calculated_on,
    )

    is_new = record.new_record?
    record.assign_attributes(
      sector_name: sector_name,
      company_count: metrics.length,
      data_json: data_json,
    )

    record.save! if record.new_record? || record.changed?
    @stats[is_new ? :created : :updated] += 1
  rescue => e
    @stats[:errors] += 1
    Rails.logger.error(
      "[CalculateSectorMetricsJob] Failed for #{classification}/#{sector_code}: #{e.message}"
    )
  end

  # 各企業のパーセンタイルランキングを算出し data_json に格納する
  def calculate_percentiles
    # セクター(33業種)単位でパーセンタイル算出
    sector_grouped = @latest_metrics.group_by { |m| m.company.sector_33_code }
    sector_grouped.each do |_sector_code, metrics|
      calculate_sector_percentiles(metrics)
    end

    # 市場全体でパーセンタイル算出
    calculate_market_percentiles(@latest_metrics)
  rescue => e
    Rails.logger.error(
      "[CalculateSectorMetricsJob] Percentile calculation failed: #{e.message}"
    )
  end

  # セクター内パーセンタイルを算出して各metricのdata_jsonに格納
  def calculate_sector_percentiles(metrics)
    FinancialMetric::SECTOR_PERCENTILE_TARGETS.each do |percentile_key, attr|
      values = metrics.map { |m| get_metric_value(m, attr) }
      compacted = values.compact.map(&:to_f)
      next if compacted.empty?

      metrics.each do |metric|
        company_value = get_metric_value(metric, attr)
        next if company_value.nil?

        pct = FinancialMetric.get_percentile(company_value.to_f, compacted)
        next if pct.nil?

        json = (metric.data_json || {}).dup
        json[percentile_key.to_s] = pct.round(4)
        metric.data_json = json
      end
    end

    metrics.each do |metric|
      metric.save! if metric.changed?
    end
  end

  # 市場全体パーセンタイルを算出して各metricのdata_jsonに格納
  def calculate_market_percentiles(metrics)
    FinancialMetric::MARKET_PERCENTILE_TARGETS.each do |percentile_key, attr|
      values = metrics.map { |m| get_metric_value(m, attr) }
      compacted = values.compact.map(&:to_f)
      next if compacted.empty?

      metrics.each do |metric|
        company_value = get_metric_value(metric, attr)
        next if company_value.nil?

        pct = FinancialMetric.get_percentile(company_value.to_f, compacted)
        next if pct.nil?

        json = (metric.data_json || {}).dup
        json[percentile_key.to_s] = pct.round(4)
        metric.data_json = json
      end
    end

    metrics.each do |metric|
      metric.save! if metric.changed?
    end
  end

  def get_metric_value(metric, attr)
    metric.public_send(attr)
  rescue NoMethodError
    nil
  end

  def log_result
    Rails.logger.info(
      "[CalculateSectorMetricsJob] Completed: " \
      "#{@stats[:created]} created, #{@stats[:updated]} updated, #{@stats[:errors]} errors"
    )
  end
end
