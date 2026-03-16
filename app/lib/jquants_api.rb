class JquantsApi
  BASE_URL = "https://api.jquants.com/v2/"

  # CurPerType → FinancialReport.report_type への変換マッピング
  PERIOD_TYPE_MAP = {
    "FY" => "annual",
    "1Q" => "q1",
    "2Q" => "q2",
    "3Q" => "q3",
  }.freeze

  class << self
    # 便利メソッド: credentials から api_key を取得してインスタンスを生成
    def default(**args)
      new(api_key: Rails.application.credentials.jquants.api_key, **args)
    end
  end

  attr_reader :api_key

  def initialize(api_key:)
    @api_key = api_key
    @connection = build_connection
  end

  # 上場銘柄一覧を取得する
  #
  # @param code [String, nil] 証券コード（5桁 or 4桁）。nilの場合は全銘柄
  # @param date [String, nil] 適用日 (YYYYMMDD or YYYY-MM-DD)。nilの場合は当日
  # @return [Array<Hash>] 銘柄情報の配列
  #   [
  #     {
  #       "Date" => "2022-11-11",
  #       "Code" => "86970",
  #       "CoName" => "日本取引所グループ",
  #       "CoNameEn" => "Japan Exchange Group,Inc.",
  #       "S17" => "16",
  #       "S17Nm" => "金融（除く銀行）",
  #       "S33" => "7200",
  #       "S33Nm" => "その他金融業",
  #       "ScaleCat" => "TOPIX Large70",
  #       "Mkt" => "0111",
  #       "MktNm" => "プライム",
  #       ...
  #     },
  #     ...
  #   ]
  #
  # 例:
  #   client = JquantsApi.default
  #   all_listed = client.load_listed_info
  #   toyota = client.load_listed_info(code: "72030")
  #
  def load_listed_info(code: nil, date: nil)
    params = {}
    params[:code] = code if code
    params[:date] = format_date(date) if date
    load_all_pages("equities/master", params)
  end

  # 株価四本値を取得する
  #
  # @param code [String, nil] 証券コード
  # @param date [String, nil] 特定日 (YYYYMMDD or YYYY-MM-DD)
  # @param from [String, nil] 開始日
  # @param to [String, nil] 終了日
  # @return [Array<Hash>] 株価データの配列
  #   [
  #     {
  #       "Date" => "2023-03-24",
  #       "Code" => "86970",
  #       "O" => 2047.0,
  #       "H" => 2069.0,
  #       "L" => 2035.0,
  #       "C" => 2045.0,
  #       "Vo" => 2202500.0,
  #       "Va" => 4507051850.0,
  #       "AdjFactor" => 1.0,
  #       "AdjC" => 2045.0,
  #       ...
  #     },
  #     ...
  #   ]
  #
  # 例:
  #   client = JquantsApi.default
  #   quotes = client.load_daily_quotes(code: "72030", from: "20240101", to: "20240131")
  #   single = client.load_daily_quotes(code: "72030", date: "20240115")
  #
  def load_daily_quotes(code: nil, date: nil, from: nil, to: nil)
    params = {}
    params[:code] = code if code
    params[:date] = format_date(date) if date
    params[:from] = format_date(from) if from
    params[:to] = format_date(to) if to
    load_all_pages("equities/bars/daily", params)
  end

  # 財務情報サマリーを取得する
  #
  # @param code [String, nil] 証券コード
  # @param date [String, nil] 開示日 (YYYYMMDD or YYYY-MM-DD)
  # @return [Array<Hash>] 財務情報の配列
  #   [
  #     {
  #       "DiscDate" => "2023-01-30",
  #       "Code" => "86970",
  #       "CurPerType" => "3Q",
  #       "Sales" => "100529000000",
  #       "OP" => "...",
  #       "NP" => "...",
  #       "EPS" => "66.76",
  #       ...
  #     },
  #     ...
  #   ]
  #
  # 例:
  #   client = JquantsApi.default
  #   statements = client.load_financial_statements(code: "72030")
  #   by_date = client.load_financial_statements(date: "20240130")
  #
  def load_financial_statements(code: nil, date: nil)
    params = {}
    params[:code] = code if code
    params[:date] = format_date(date) if date
    load_all_pages("fins/summary", params)
  end

  # 決算発表予定日を取得する
  #
  # @param code [String, nil] 証券コード
  # @param date [String, nil] 発表予定日
  # @return [Array<Hash>] 決算発表予定日の配列
  #
  # 例:
  #   client = JquantsApi.default
  #   calendar = client.load_earnings_calendar(date: "20240130")
  #
  def load_earnings_calendar(code: nil, date: nil)
    params = {}
    params[:code] = code if code
    params[:date] = format_date(date) if date
    load_all_pages("equities/earnings-calendar", params)
  end

  # ページネーションを自動処理し、全ページのデータを結合して返す
  #
  # @param path [String] エンドポイントパス（ベースURLからの相対パス）
  # @param params [Hash] クエリパラメータ
  # @return [Array<Hash>] 全ページ結合済みのデータ配列
  def load_all_pages(path, params = {})
    all_data = []
    loop do
      response = get(path, params)
      parsed = JSON.parse(response.body)
      data = parsed["data"] || []
      all_data.concat(data)

      pagination_key = parsed["pagination_key"]
      break if pagination_key.nil? || pagination_key.empty?

      params = params.merge(pagination_key: pagination_key)
    end
    all_data
  end

  private

  def build_connection
    Faraday.new(url: BASE_URL) do |conn|
      conn.headers["x-api-key"] = @api_key
      conn.request :retry,
        max: 4,
        interval: 3,
        backoff_factor: 2,
        retry_statuses: [429, 500, 502, 503],
        exceptions: Faraday::Retry::Middleware::DEFAULT_EXCEPTIONS +
                    [Faraday::TooManyRequestsError]
      conn.response :raise_error
      conn.adapter Faraday.default_adapter
    end
  end

  def get(path, params = {})
    @connection.get(path, params)
  end

  # 日付文字列をAPIが受け付ける形式に正規化する
  # Date型はYYYY-MM-DD形式に変換、文字列はそのまま許容
  def format_date(date)
    return nil unless date
    if date.is_a?(Date)
      date.strftime("%Y-%m-%d")
    else
      date.to_s
    end
  end
end
