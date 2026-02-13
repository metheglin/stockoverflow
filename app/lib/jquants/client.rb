module Jquants
  class Client < ApiClient::Base
    BASE_URL = "https://api.jquants.com/v2"

    PLAN_INTERVALS = {
      free: 60.0 / 5,
      light: 60.0 / 60,
      standard: 60.0 / 120,
      premium: 60.0 / 120
    }.freeze

    def initialize(api_key: nil, plan: :free, logger: nil)
      @api_key = api_key || resolve_api_key
      interval = PLAN_INTERVALS.fetch(plan, PLAN_INTERVALS[:free])
      rate_limiter = ApiClient::RateLimiter.new(min_interval: interval)
      super(base_url: BASE_URL, rate_limiter: rate_limiter, logger: logger)
    end

    # 上場企業マスタ
    # @param code [String, nil] 銘柄コード
    # @param date [Date, String, nil] 基準日
    # @return [Array<Hash>]
    def listed_companies(code: nil, date: nil)
      params = {}
      params[:code] = code if code
      params[:date] = format_date(date) if date
      paginate("/equities/master", params: params).all
    end

    # 日次株価
    # @param code [String, nil] 銘柄コード
    # @param date [Date, String, nil] 指定日
    # @param from [Date, String, nil] 期間開始
    # @param to [Date, String, nil] 期間終了
    # @return [Array<Hash>]
    def daily_prices(code: nil, date: nil, from: nil, to: nil)
      params = {}
      params[:code] = code if code
      params[:date] = format_date(date) if date
      params[:from] = format_date(from) if from
      params[:to] = format_date(to) if to
      paginate("/equities/bars/daily", params: params).all
    end

    # 財務サマリ（四半期決算）
    # @param code [String, nil] 銘柄コード
    # @param date [Date, String, nil] 開示日
    # @return [Array<Hash>]
    def financial_summary(code: nil, date: nil)
      params = {}
      params[:code] = code if code
      params[:date] = format_date(date) if date
      paginate("/fins/summary", params: params).all
    end

    # 配当情報（Premiumプラン）
    # @param code [String, nil] 銘柄コード
    # @param date [Date, String, nil] 基準日
    # @return [Array<Hash>]
    def dividends(code: nil, date: nil)
      params = {}
      params[:code] = code if code
      params[:date] = format_date(date) if date
      paginate("/fins/dividend", params: params).all
    end

    # 財務明細 BS/PL/CF（Premiumプラン）
    # @param code [String, nil] 銘柄コード
    # @param date [Date, String, nil] 基準日
    # @return [Array<Hash>]
    def financial_details(code: nil, date: nil)
      params = {}
      params[:code] = code if code
      params[:date] = format_date(date) if date
      paginate("/fins/details", params: params).all
    end

    # Paginatorを返す（ページ単位のストリーミング用）
    # @param path [String] エンドポイントパス
    # @param params [Hash] クエリパラメータ
    # @return [Jquants::Paginator]
    def paginate(path, params: {})
      Jquants::Paginator.new(client: self, path: path, params: params)
    end

    private

    def authenticated_get(path, params: {})
      get(path, params: params, headers: { "x-api-key" => @api_key })
    end

    def resolve_api_key
      Rails.application.credentials.dig(:jquants, :api_key) ||
        ENV["JQUANTS_API_KEY"] ||
        raise(ApiClient::Errors::AuthenticationError.new(
          "J-Quants API key not configured. Set via Rails credentials (jquants.api_key) or ENV['JQUANTS_API_KEY']."
        ))
    end

    def format_date(date)
      return nil if date.nil?
      date.respond_to?(:strftime) ? date.strftime("%Y-%m-%d") : date.to_s
    end
  end
end
