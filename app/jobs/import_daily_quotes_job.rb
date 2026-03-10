class ImportDailyQuotesJob < ApplicationJob
  SLEEP_BETWEEN_COMPANIES = 1  # 銘柄間の待機秒数（全件取得モード用）

  # 株価四本値データを取り込む
  #
  # @param full [Boolean] trueの場合全上場企業の過去データを取得
  # @param from_date [String, nil] 取得開始日 (YYYY-MM-DD)
  # @param to_date [String, nil] 取得終了日 (YYYY-MM-DD)
  # @param api_key [String, nil] APIキー
  #
  def perform(full: false, from_date: nil, to_date: nil, api_key: nil)
    @client = api_key ? JquantsApi.new(api_key: api_key) : JquantsApi.default
    @stats = { imported: 0, skipped: 0, errors: 0 }

    if full
      import_full(from_date: from_date, to_date: to_date)
    else
      import_incremental(from_date: from_date, to_date: to_date)
    end

    record_sync_date(to_date ? Date.parse(to_date) : Date.current)
    log_result
  end

  private

  # 全上場企業について銘柄指定で取得
  def import_full(from_date: nil, to_date: nil)
    from = from_date || "20200101"
    to = to_date || Date.current.strftime("%Y%m%d")

    Company.listed.where.not(securities_code: nil).find_each do |company|
      begin
        quotes = @client.load_daily_quotes(
          code: company.securities_code, from: from, to: to
        )
        import_quotes(quotes, company: company)
      rescue => e
        @stats[:errors] += 1
        Rails.logger.error(
          "[ImportDailyQuotesJob] API error for #{company.securities_code}: #{e.message}"
        )
      end

      sleep(SLEEP_BETWEEN_COMPANIES)
    end
  end

  # 差分取得: 最終同期日から当日まで日付指定で取得
  def import_incremental(from_date: nil, to_date: nil)
    start_date = from_date ? Date.parse(from_date) : get_last_synced_date
    end_date = to_date ? Date.parse(to_date) : Date.current

    (start_date..end_date).each do |date|
      # 土日はスキップ（株式市場は営業日のみ）
      next if date.saturday? || date.sunday?

      begin
        quotes = @client.load_daily_quotes(date: date.strftime("%Y%m%d"))
        import_quotes(quotes)
      rescue => e
        @stats[:errors] += 1
        Rails.logger.error(
          "[ImportDailyQuotesJob] API error for date #{date}: #{e.message}"
        )
      end
    end
  end

  # 株価データ配列をDBに保存
  #
  # @param quotes [Array<Hash>] JQUANTSレスポンスの株価データ配列
  # @param company [Company, nil] 事前に特定済みの企業（nil時はCodeから検索）
  def import_quotes(quotes, company: nil)
    quotes.each do |data|
      import_quote(data, company: company)
    end
  end

  # 1件の株価データをDBに保存
  def import_quote(data, company: nil)
    code = data["Code"]
    traded_on = parse_date(data["Date"])
    return if code.blank? || traded_on.nil?

    company ||= Company.find_by(securities_code: code)
    unless company
      @stats[:skipped] += 1
      return
    end

    attrs = DailyQuote.get_attributes_from_jquants(data)
    quote = DailyQuote.find_or_initialize_by(
      company: company,
      traded_on: traded_on,
    )
    quote.assign_attributes(attrs)
    quote.save! if quote.new_record? || quote.changed?

    @stats[:imported] += 1
  rescue => e
    @stats[:errors] += 1
    Rails.logger.error(
      "[ImportDailyQuotesJob] Failed to import #{code}/#{data["Date"]}: #{e.message}"
    )
  end

  # 最終同期日を取得（未設定時は7日前）
  def get_last_synced_date
    prop = ApplicationProperty.find_by(kind: :jquants_sync)
    if prop&.last_synced_date.present?
      Date.parse(prop.last_synced_date)
    else
      7.days.ago.to_date
    end
  end

  # 最終同期日を記録
  def record_sync_date(date)
    prop = ApplicationProperty.find_or_create_by!(kind: :jquants_sync)
    prop.last_synced_date = date.iso8601
    prop.save!
  end

  def log_result
    Rails.logger.info(
      "[ImportDailyQuotesJob] Completed: " \
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
