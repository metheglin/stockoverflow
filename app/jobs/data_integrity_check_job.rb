class DataIntegrityCheckJob < ApplicationJob
  QUOTE_STALE_THRESHOLD_DAYS = 7

  # データ整合性チェックジョブ
  #
  # 各種データの整合性を検証し、結果をApplicationPropertyに保存する。
  # 検出された問題は構造化ログとして出力する。
  #
  def perform
    @issues = []
    @summary = {}

    check_missing_metrics
    check_missing_daily_quotes
    check_consecutive_growth_integrity
    check_sync_freshness
    generate_summary

    save_results
    log_results
  end

  # financial_values に対応する financial_metrics が存在しないレコードを検出する
  #
  # @return [Hash] { missing_count: Integer, total_count: Integer, sample_ids: Array }
  def check_missing_metrics
    total = FinancialValue.count
    missing = FinancialValue.left_joins(:financial_metric)
                            .where(financial_metrics: { id: nil })

    missing_count = missing.count
    sample_ids = missing.limit(10).pluck(:id)

    @summary[:missing_metrics] = {
      missing_count: missing_count,
      total_financial_values: total,
    }

    if missing_count > 0
      add_issue(
        check: "missing_metrics",
        severity: "warning",
        message: "#{missing_count}件のfinancial_valuesに対応するfinancial_metricsが未算出",
        details: { missing_count: missing_count, sample_ids: sample_ids },
      )
    end
  end

  # 上場企業に対して直近の daily_quotes が存在するかを検出する
  #
  # @return [Hash] { missing_count: Integer, total_listed: Integer }
  def check_missing_daily_quotes
    listed_companies = Company.listed
    total_listed = listed_companies.count
    threshold_date = Date.current - QUOTE_STALE_THRESHOLD_DAYS

    companies_with_recent_quotes = DailyQuote
      .where("traded_on >= ?", threshold_date)
      .distinct
      .pluck(:company_id)

    missing_companies = listed_companies
      .where.not(id: companies_with_recent_quotes)

    missing_count = missing_companies.count
    sample_codes = missing_companies.limit(10).pluck(:securities_code)

    @summary[:missing_daily_quotes] = {
      missing_count: missing_count,
      total_listed: total_listed,
    }

    if missing_count > 0
      add_issue(
        check: "missing_daily_quotes",
        severity: "warning",
        message: "#{missing_count}件の上場企業に直近#{QUOTE_STALE_THRESHOLD_DAYS}日間のdaily_quotesが存在しない",
        details: { missing_count: missing_count, sample_codes: sample_codes },
      )
    end
  end

  # consecutive_revenue_growth / consecutive_profit_growth の整合性を検証する
  def check_consecutive_growth_integrity
    anomaly_count = 0
    checked_companies = 0

    Company.listed.find_each do |company|
      metrics = FinancialMetric
        .where(company_id: company.id, scope: :consolidated, period_type: :annual)
        .order(:fiscal_year_end)
        .pluck(:fiscal_year_end, :revenue_yoy, :net_income_yoy,
               :consecutive_revenue_growth, :consecutive_profit_growth)

      next if metrics.size < 2

      metric_hashes = metrics.map do |row|
        {
          fiscal_year_end: row[0],
          revenue_yoy: row[1],
          net_income_yoy: row[2],
          consecutive_revenue_growth: row[3],
          consecutive_profit_growth: row[4],
        }
      end

      anomalies = FinancialMetric.detect_consecutive_anomalies(metric_hashes)
      if anomalies.any?
        anomaly_count += anomalies.size
        add_issue(
          check: "consecutive_growth_integrity",
          severity: "error",
          message: "企業#{company.securities_code}の連続増収増益期数に#{anomalies.size}件の不整合",
          details: {
            company_id: company.id,
            securities_code: company.securities_code,
            anomalies: anomalies.first(5),
          },
        )
      end

      checked_companies += 1
    end

    @summary[:consecutive_growth] = {
      checked_companies: checked_companies,
      anomaly_count: anomaly_count,
    }
  end

  # application_properties の last_synced_date が古すぎないかを検出する
  def check_sync_freshness
    sync_statuses = {}

    [:edinet_sync, :jquants_sync].each do |kind|
      prop = ApplicationProperty.find_by(kind: kind)

      if prop.nil?
        sync_statuses[kind] = { stale: true, days_since_sync: nil, message: "同期レコード未作成" }
        add_issue(
          check: "sync_freshness",
          severity: "error",
          message: "#{kind}のApplicationPropertyレコードが存在しない",
          details: { kind: kind.to_s },
        )
        next
      end

      staleness = ApplicationProperty.get_sync_staleness(
        prop.last_synced_date,
        reference_date: Date.current,
      )
      sync_statuses[kind] = staleness

      if staleness[:stale]
        add_issue(
          check: "sync_freshness",
          severity: "warning",
          message: "#{kind}の最終同期日が#{staleness[:days_since_sync] || '不明'}日前（閾値: #{ApplicationProperty::SYNC_STALE_THRESHOLD_DAYS}日）",
          details: { kind: kind.to_s, **staleness },
        )
      end
    end

    @summary[:sync_freshness] = sync_statuses
  end

  # データの集計サマリーを生成する
  def generate_summary
    @summary[:data_counts] = {
      listed_companies: Company.listed.count,
      total_companies: Company.count,
      financial_values_total: FinancialValue.count,
      financial_values_annual: FinancialValue.where(period_type: :annual).count,
      financial_values_quarterly: FinancialValue.where(period_type: [:q1, :q2, :q3]).count,
      financial_metrics_total: FinancialMetric.count,
      daily_quotes_total: DailyQuote.count,
      daily_quotes_latest_date: DailyQuote.maximum(:traded_on)&.to_s,
    }

    @summary[:source_counts] = {
      edinet_reports: FinancialReport.where(source: :edinet).count,
      jquants_reports: FinancialReport.where(source: :jquants).count,
    }

    @summary[:checked_at] = Time.current.iso8601
    @summary[:issue_count] = @issues.size
  end

  private

  def add_issue(check:, severity:, message:, details: {})
    issue = {
      check: check,
      severity: severity,
      message: message,
      details: details,
      detected_at: Time.current.iso8601,
    }
    @issues << issue

    log_entry = {
      job: "DataIntegrityCheckJob",
      event: "issue_detected",
      check: check,
      severity: severity,
      message: message,
      **details,
    }.to_json

    case severity
    when "error"
      Rails.logger.error(log_entry)
    when "warning"
      Rails.logger.warn(log_entry)
    end
  end

  def save_results
    prop = ApplicationProperty.find_or_initialize_by(kind: :data_integrity)
    prop.data_json = {
      "summary" => @summary.deep_stringify_keys,
      "issues" => @issues,
      "last_checked_at" => Time.current.iso8601,
    }
    prop.save!
  end

  def log_results
    Rails.logger.info(
      {
        job: "DataIntegrityCheckJob",
        event: "completed",
        issue_count: @issues.size,
        issues_by_severity: @issues.group_by { |i| i[:severity] }.transform_values(&:size),
        summary: @summary.except(:sync_freshness),
      }.to_json
    )
  end
end
