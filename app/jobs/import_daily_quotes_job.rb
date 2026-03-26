class ImportDailyQuotesJob < ApplicationJob
  SLEEP_BETWEEN_COMPANIES = 1  # 銘柄間の待機秒数（全件取得モード用）
  MAX_SUBSCRIPTION_ERRORS = 3  # サブスクリプション範囲エラーの許容回数（超過で中断）

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
    @subscription_errors = 0

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
    from = from_date ? Date.parse(from_date) : Date.new(2020, 1, 1)
    to = to_date ? Date.parse(to_date) : Date.current

    Company.listed.where.not(securities_code: nil).find_each do |company|
      company_retried = false
      begin
        quotes = @client.load_daily_quotes(
          code: company.securities_code,
          from: from.strftime("%Y%m%d"),
          to: to.strftime("%Y%m%d")
        )
        import_quotes(quotes, company: company)
      rescue JquantsApi::SubscriptionRangeError => e
        unless company_retried
          from, to = clamp_date_range(from, to, e)
          company_retried = true
          retry
        end
        @stats[:errors] += 1
        Rails.logger.warn(
          "[ImportDailyQuotesJob] Subscription range error for #{company.securities_code}: " \
          "available #{e.available_from} ~ #{e.available_to}, skipping"
        )
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
    first_request = true

    (start_date..end_date).each do |date|
      next if date.saturday? || date.sunday?
      next if @subscription_range && !date.between?(@subscription_range[:from], @subscription_range[:to])

      begin
        sleep(SLEEP_BETWEEN_COMPANIES) unless first_request
        first_request = false
        quotes = @client.load_daily_quotes(date: date.strftime("%Y%m%d"))
        import_quotes(quotes)
      rescue JquantsApi::SubscriptionRangeError => e
        @subscription_range = { from: e.available_from, to: e.available_to }
        handle_subscription_error!(e, context: date.iso8601)
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

  # サブスクリプション範囲エラーの処理
  # エラー回数が上限を超えた場合は例外を発生させてジョブを中断する
  def handle_subscription_error!(error, context:)
    @subscription_errors += 1
    @stats[:errors] += 1

    Rails.logger.warn(
      "[ImportDailyQuotesJob] Subscription range error " \
      "(#{@subscription_errors}/#{MAX_SUBSCRIPTION_ERRORS}) " \
      "for #{context}: available #{error.available_from} ~ #{error.available_to}"
    )

    if @subscription_errors >= MAX_SUBSCRIPTION_ERRORS
      raise JquantsApi::SubscriptionRangeError.new(
        "Aborting: subscription range error occurred #{@subscription_errors} times. " \
        "Available: #{error.available_from} ~ #{error.available_to}",
        available_from: error.available_from,
        available_to: error.available_to
      )
    end
  end

  # 日付範囲をサブスクリプションの利用可能範囲にクランプする
  #
  # @param from [Date] 開始日
  # @param to [Date] 終了日
  # @param error [JquantsApi::SubscriptionRangeError] サブスクリプション範囲エラー
  # @return [Array<Date>] クランプ後の [from, to]
  def clamp_date_range(from, to, error)
    clamped_from = [from, error.available_from].max
    clamped_to = [to, error.available_to].min

    Rails.logger.info(
      "[ImportDailyQuotesJob] Clamping date range: " \
      "#{from} ~ #{to} -> #{clamped_from} ~ #{clamped_to}"
    )

    [clamped_from, clamped_to]
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
