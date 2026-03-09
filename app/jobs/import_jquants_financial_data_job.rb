class ImportJquantsFinancialDataJob < ApplicationJob
  # JQUANTS財務情報サマリーを取り込む
  #
  # @param full [Boolean] trueの場合全上場企業の全期間を取得、falseの場合差分のみ
  # @param api_key [String, nil] APIキー。nilの場合はcredentialsから取得
  # @param target_date [String, nil] 特定日のみ取り込む場合に指定 (YYYY-MM-DD)
  #
  def perform(full: false, api_key: nil, target_date: nil)
    @client = api_key ? JquantsApi.new(api_key: api_key) : JquantsApi.default
    @stats = { imported: 0, skipped: 0, errors: 0 }

    if target_date
      import_by_date(target_date)
    elsif full
      import_full
    else
      import_incremental
    end

    record_sync_date
    log_result
  end

  private

  # 全上場企業について銘柄指定で全期間取得
  def import_full
    Company.listed.find_each do |company|
      next if company.securities_code.blank?

      begin
        statements = @client.load_financial_statements(code: company.securities_code)
        statements.each { |data| import_statement(data, company: company) }
      rescue => e
        @stats[:errors] += 1
        Rails.logger.error(
          "[ImportJquantsFinancialDataJob] API error for #{company.securities_code}: #{e.message}"
        )
      end
    end
  end

  # 差分取得: 最終同期日から今日まで日付指定で取得
  def import_incremental
    start_date = get_last_synced_date
    end_date = Date.current

    (start_date..end_date).each do |date|
      import_by_date(date)
    end
  end

  # 指定日の全銘柄決算データを取得
  def import_by_date(date)
    date = Date.parse(date.to_s) unless date.is_a?(Date)
    statements = @client.load_financial_statements(date: date.strftime("%Y%m%d"))
    statements.each { |data| import_statement(data) }
  rescue => e
    @stats[:errors] += 1
    Rails.logger.error(
      "[ImportJquantsFinancialDataJob] API error for date #{date}: #{e.message}"
    )
  end

  # 1件の財務情報サマリーを取り込む
  #
  # @param data [Hash] JQUANTSレスポンスの1件分
  # @param company [Company, nil] 事前に特定済みの企業（nil時はcodeから検索）
  def import_statement(data, company: nil)
    code = data["Code"]
    return if code.blank?

    company ||= Company.find_by(securities_code: code)
    unless company
      @stats[:skipped] += 1
      return
    end

    report_type = JquantsApi::PERIOD_TYPE_MAP[data["CurPerType"]]
    return if report_type.nil?

    fiscal_year_end = parse_date(data["CurFYEn"])
    return if fiscal_year_end.nil?

    # financial_report を作成/更新
    doc_id = "JQ_#{code}_#{data["CurFYEn"]}_#{data["CurPerType"]}"
    report = FinancialReport.find_or_initialize_by(doc_id: doc_id)
    report.assign_attributes(
      company: company,
      report_type: report_type,
      source: :jquants,
      fiscal_year_start: parse_date(data["CurFYSt"]),
      fiscal_year_end: fiscal_year_end,
      period_start: parse_date(data["CurPerSt"]),
      period_end: parse_date(data["CurPerEn"]),
      disclosed_at: parse_date(data["DiscDate"]),
    )
    report.save! if report.new_record? || report.changed?

    # 連結 financial_value を作成/更新
    import_financial_value(
      data, company: company, report: report,
      fiscal_year_end: fiscal_year_end,
      period_type: report_type,
      scope_type: :consolidated
    )

    # 個別 financial_value を作成/更新（NC*フィールドに値がある場合のみ）
    if has_non_consolidated_data?(data)
      import_financial_value(
        data, company: company, report: report,
        fiscal_year_end: fiscal_year_end,
        period_type: report_type,
        scope_type: :non_consolidated
      )
    end

    @stats[:imported] += 1
  rescue => e
    @stats[:errors] += 1
    Rails.logger.error(
      "[ImportJquantsFinancialDataJob] Failed to import #{data["Code"]}/#{data["CurFYEn"]}: #{e.message}"
    )
  end

  # financial_value の作成/更新
  def import_financial_value(data, company:, report:, fiscal_year_end:, period_type:, scope_type:)
    scope_int = scope_type == :consolidated ? 0 : 1
    period_type_int = FinancialValue.period_types[period_type]

    fv = FinancialValue.find_or_initialize_by(
      company: company,
      fiscal_year_end: fiscal_year_end,
      scope: scope_int,
      period_type: period_type_int,
    )

    attrs = FinancialValue.get_attributes_from_jquants(data, scope_type: scope_type)
    attrs[:financial_report] = report

    # 既存のdata_jsonがある場合はマージ（EDINET由来の拡張データを保持）
    if fv.persisted? && fv.data_json.present? && attrs[:data_json].present?
      attrs[:data_json] = fv.data_json.merge(attrs[:data_json])
    end

    fv.assign_attributes(attrs)
    fv.save! if fv.new_record? || fv.changed?
  end

  # 個別決算データの有無を判定
  def has_non_consolidated_data?(data)
    %w[NCSales NCOP NCNP NCTA].any? { |key| data[key].present? && data[key] != "" }
  end

  # 最終同期日を取得（未設定時は90日前）
  def get_last_synced_date
    prop = ApplicationProperty.find_by(kind: :jquants_sync)
    if prop&.last_synced_date.present?
      Date.parse(prop.last_synced_date)
    else
      90.days.ago.to_date
    end
  end

  # 最終同期日を記録
  def record_sync_date
    prop = ApplicationProperty.find_or_create_by!(kind: :jquants_sync)
    prop.last_synced_date = Date.current.iso8601
    prop.save!
  end

  def log_result
    Rails.logger.info(
      "[ImportJquantsFinancialDataJob] Completed: " \
      "#{@stats[:imported]} imported, #{@stats[:skipped]} skipped, #{@stats[:errors]} errors"
    )
  end

  def parse_date(value)
    return nil if value.blank?
    Date.parse(value)
  rescue Date::Error
    nil
  end
end
