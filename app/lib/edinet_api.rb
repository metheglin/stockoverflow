class EdinetApi
  BASE_URL = "https://api.edinet-fsa.go.jp/api/v2/"

  DOC_TYPE_CODES = {
    annual_securities_report: "120",
    amended_annual_securities_report: "130",
    quarterly_securities_report: "140",
    amended_quarterly_securities_report: "150",
    semi_annual_securities_report: "160",
    amended_semi_annual_securities_report: "170",
  }.freeze

  # 対象書類のdocTypeCode一覧（絞り込み用）
  TARGET_DOC_TYPE_CODES = %w[120 130 140 150 160 170].freeze

  class << self
    # 便利メソッド: credentials から api_key を取得してインスタンスを生成
    def default(**args)
      new(api_key: Rails.application.credentials.edinet.api_key, **args)
    end
  end

  attr_reader :api_key

  def initialize(api_key:)
    @api_key = api_key
    @connection = build_connection
  end

  # 書類一覧を取得する
  #
  # @param date [String, Date] 取得対象日 (YYYY-MM-DD形式 or Date)
  # @param include_documents [Boolean] trueの場合type=2（書類一覧+メタデータ）、falseの場合type=1（メタデータのみ）
  # @return [Hash] APIレスポンスのパース済みJSON
  #   {
  #     "metadata" => { "resultset" => { "count" => 182 }, "status" => "200", ... },
  #     "results" => [ { "docID" => "S100XXXX", "edinetCode" => "E12345", ... }, ... ]
  #   }
  #
  # 例:
  #   client = EdinetApi.default
  #   response = client.load_documents(date: "2024-06-25", include_documents: true)
  #   response["results"].each { |doc| puts doc["docID"] }
  #
  def load_documents(date:, include_documents: true)
    params = {
      date: date.is_a?(Date) ? date.strftime("%Y-%m-%d") : date,
      type: include_documents ? 2 : 1,
    }
    response = get("documents.json", params)
    JSON.parse(response.body)
  end

  # 指定日の書類一覧から対象書類種別のみを抽出して返す
  #
  # @param date [String, Date] 取得対象日
  # @param doc_type_codes [Array<String>] 対象docTypeCodeの配列（デフォルト: TARGET_DOC_TYPE_CODES）
  # @return [Array<Hash>] 絞り込み済みの書類情報配列
  #
  # 例:
  #   client = EdinetApi.default
  #   docs = client.load_target_documents(date: "2024-06-25")
  #   docs.each { |doc| puts "#{doc["filerName"]}: #{doc["docDescription"]}" }
  #
  def load_target_documents(date:, doc_type_codes: TARGET_DOC_TYPE_CODES)
    result = load_documents(date: date, include_documents: true)
    results = result["results"] || []
    results.select do |doc|
      doc_type_codes.include?(doc["docTypeCode"]) &&
        doc["xbrlFlag"] == "1" &&
        doc["withdrawalStatus"] == "0"
    end
  end

  # 書類のXBRLデータをZIPとしてダウンロードし、一時ファイルに保存して返す
  #
  # @param doc_id [String] 書類管理番号
  # @return [Tempfile] ZIPファイルが書き込まれたTempfile
  #
  # 例:
  #   client = EdinetApi.default
  #   zip_file = client.load_xbrl_zip(doc_id: "S100TDUA")
  #   # zip_file.path で一時ファイルのパスを取得可能
  #
  def load_xbrl_zip(doc_id:)
    response = get("documents/#{doc_id}", { type: 1 })
    tempfile = Tempfile.new(["edinet_#{doc_id}_", ".zip"], binmode: true)
    tempfile.write(response.body)
    tempfile.rewind
    tempfile
  end

  # 書類のCSVデータをZIPとしてダウンロードし、一時ファイルに保存して返す
  #
  # @param doc_id [String] 書類管理番号
  # @return [Tempfile] ZIPファイルが書き込まれたTempfile
  #
  def load_csv_zip(doc_id:)
    response = get("documents/#{doc_id}", { type: 5 })
    tempfile = Tempfile.new(["edinet_csv_#{doc_id}_", ".zip"], binmode: true)
    tempfile.write(response.body)
    tempfile.rewind
    tempfile
  end

  private

  def build_connection
    Faraday.new(url: BASE_URL) do |conn|
      conn.request :retry, max: 2, interval: 3, backoff_factor: 2
      conn.response :raise_error
      conn.adapter Faraday.default_adapter
    end
  end

  def get(path, params = {})
    @connection.get(path, params.merge("Subscription-Key" => @api_key))
  end
end
