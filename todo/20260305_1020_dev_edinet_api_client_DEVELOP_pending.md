# EDINET APIクライアント・XBRLパーサー実装

## 概要

EDINET API v2 を利用して有価証券報告書等の開示書類を取得し、XBRLデータから財務数値を抽出するためのクライアント・パーサーを実装する。

`app/lib/` に配置し、コーディング規約の「汎用性と利便性」の方針に従って設計する。

## 前提知識

### EDINET API v2

- ベースURL: `https://api.edinet-fsa.go.jp/api/v2/`
- 認証: クエリパラメータ `Subscription-Key` にAPIキーを指定
- APIキー: `Rails.application.credentials.edinet.api_key`
- 主要エンドポイント:
  - 書類一覧API: `GET /api/v2/documents.json`
  - 書類取得API: `GET /api/v2/documents/{docID}`
- レスポンス: 書類一覧はJSON、書類取得はZIPバイナリ（XBRL/PDF/CSV）

### レート制限（推奨アクセス頻度）

- 書類一覧API: 1分に1回以下（書類一覧は1分に1回程度しか更新されない）
- 書類取得API: リクエスト間3〜5秒のスリープ推奨
- 超過時: 429 Too Many Requests、レスポンス遅延、一時的なBAN

### 対象書類種別（docTypeCode）

| docTypeCode | 書類種別 | report_type への変換 |
|---|---|---|
| `120` | 有価証券報告書 | `annual` |
| `130` | 訂正有価証券報告書 | （120と同じ report に紐づけ） |
| `140` | 四半期報告書 | `q1` / `q2` / `q3`（期間から判定） |
| `150` | 訂正四半期報告書 | （140と同じ report に紐づけ） |
| `160` | 半期報告書 | `semi_annual` |
| `170` | 訂正半期報告書 | （160と同じ report に紐づけ） |

### XBRL

- XBRLはXMLベースの財務報告標準言語
- 書類取得API（type=1）でZIPをダウンロードし、ZIP内の `XBRL/PublicDoc/` 配下にXBRLインスタンスファイル（.xbrl）が格納される
- 財務諸表の名前空間: `jppfs_cor`（日本基準）、`jpigp_cor`（IFRS）
- パースには Nokogiri を使用（既存のXBRL用Ruby gemは古くメンテナンスされていないため自前実装）

---

## 実装タスク

### タスク1: EdinetApi クライアント

#### ファイル: `app/lib/edinet_api.rb`

EDINET API v2へのHTTPリクエストを担うクライアント。Faradayを使用する。

```ruby
class EdinetApi
  BASE_URL = "https://api.edinet-fsa.go.jp/api/v2"

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
    response = get("/documents.json", params)
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
    response = get("/documents/#{doc_id}", { type: 1 })
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
    response = get("/documents/#{doc_id}", { type: 5 })
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
```

#### 設計判断

- **コーディング規約「汎用性と利便性」準拠**: `api_key` をコンストラクタ引数で受け取り、`EdinetApi.default` 便利メソッドでcredentialsからの取得を提供
- **エラーハンドリング**: `Faraday::Response::RaiseError` を使い、4xx/5xxレスポンスでFaradayの例外を発生させる。エラーハンドリング規約に従い、クライアント側では例外を捕捉せず呼び出し元に委ねる
- **リトライ**: `faraday-retry` gemを活用。ネットワーク一時障害やサーバーエラー時に自動リトライ（最大2回、3秒間隔、バックオフ2倍）
- **命名規約**: `load_documents`, `load_xbrl_zip` はAPI呼び出しを伴うため `load_` プレフィックス。`load_target_documents` も内部で `load_documents` を呼ぶためI/Oを伴う処理
- **ZIPダウンロード**: Tempfileに書き込んで返す。呼び出し元がZIP展開・パースの責務を持つ

#### テスト: `spec/lib/edinet_api_spec.rb`

テスティング規約に従い、APIKEYが指定されている場合は実際のAPI呼び出しテストを記述する。ただし影響が限定的な読み取り系のみ。

```ruby
RSpec.describe EdinetApi do
  # credentialsにAPIキーが設定されている場合のみ実行
  # EDINET_API_KEY 環境変数でのオーバーライドも可能
  let(:api_key) do
    ENV["EDINET_API_KEY"] || Rails.application.credentials.dig(:edinet, :api_key)
  end

  before do
    skip "EDINET API key not configured" unless api_key
  end

  describe "#load_documents" do
    it "指定日の書類一覧を取得できる" do
      client = EdinetApi.new(api_key: api_key)
      result = client.load_documents(date: "2024-06-25", include_documents: true)

      expect(result).to have_key("metadata")
      expect(result).to have_key("results")
      expect(result["metadata"]["status"]).to eq("200")
      expect(result["results"]).to be_an(Array)
    end

    it "Date型でも指定できる" do
      client = EdinetApi.new(api_key: api_key)
      result = client.load_documents(date: Date.new(2024, 6, 25))

      expect(result["metadata"]["status"]).to eq("200")
    end
  end

  describe "#load_target_documents" do
    it "対象書類種別のみに絞り込まれる" do
      client = EdinetApi.new(api_key: api_key)
      docs = client.load_target_documents(date: "2024-06-25")

      expect(docs).to be_an(Array)
      docs.each do |doc|
        expect(EdinetApi::TARGET_DOC_TYPE_CODES).to include(doc["docTypeCode"])
        expect(doc["xbrlFlag"]).to eq("1")
        expect(doc["withdrawalStatus"]).to eq("0")
      end
    end
  end

  describe ".default" do
    it "credentialsのAPIキーでインスタンスを生成できる" do
      skip "credentials not configured" unless Rails.application.credentials.dig(:edinet, :api_key)
      client = EdinetApi.default
      expect(client.api_key).to eq(Rails.application.credentials.edinet.api_key)
    end
  end
end
```

---

### タスク2: EdinetXbrlParser

#### ファイル: `app/lib/edinet_xbrl_parser.rb`

EDINET書類取得APIからダウンロードしたZIPファイルを展開し、XBRLインスタンスファイルから財務数値を抽出するパーサー。

```ruby
class EdinetXbrlParser
  # 抽出対象のXBRL要素マッピング
  #
  # financial_values の固定カラムに対応するXBRL要素名を定義
  # キー: financial_values カラム名（Symbol）
  # 値: { elements: [要素名の候補配列], namespace: 名前空間 }
  #
  # 要素名の候補を配列にしているのは、企業によって使用する勘定科目が異なる場合があるため。
  # 配列の先頭から順に検索し、最初に見つかった値を採用する。
  ELEMENT_MAPPING = {
    # P/L
    net_sales: {
      elements: ["NetSales", "OperatingRevenue1", "OperatingRevenue2", "Revenue1"],
      namespace: "jppfs_cor",
    },
    operating_income: {
      elements: ["OperatingIncome", "OperatingProfit"],
      namespace: "jppfs_cor",
    },
    ordinary_income: {
      elements: ["OrdinaryIncome", "OrdinaryProfit"],
      namespace: "jppfs_cor",
    },
    net_income: {
      elements: ["ProfitLossAttributableToOwnersOfParent", "ProfitLoss", "NetIncome"],
      namespace: "jppfs_cor",
    },

    # B/S
    total_assets: {
      elements: ["Assets"],
      namespace: "jppfs_cor",
    },
    net_assets: {
      elements: ["NetAssets"],
      namespace: "jppfs_cor",
    },

    # C/F
    operating_cf: {
      elements: ["NetCashProvidedByUsedInOperatingActivities"],
      namespace: "jppfs_cor",
    },
    investing_cf: {
      elements: ["NetCashProvidedByUsedInInvestmentActivities"],
      namespace: "jppfs_cor",
    },
    financing_cf: {
      elements: ["NetCashProvidedByUsedInFinancingActivities"],
      namespace: "jppfs_cor",
    },
    cash_and_equivalents: {
      elements: ["CashAndCashEquivalentsAtEndOfPeriod", "CashAndCashEquivalents"],
      namespace: "jppfs_cor",
    },
  }.freeze

  # data_json に格納する拡張要素マッピング
  EXTENDED_ELEMENT_MAPPING = {
    cost_of_sales: {
      elements: ["CostOfSales"],
      namespace: "jppfs_cor",
    },
    gross_profit: {
      elements: ["GrossProfit"],
      namespace: "jppfs_cor",
    },
    sga_expenses: {
      elements: ["SellingGeneralAndAdministrativeExpenses"],
      namespace: "jppfs_cor",
    },
    current_assets: {
      elements: ["CurrentAssets"],
      namespace: "jppfs_cor",
    },
    noncurrent_assets: {
      elements: ["NoncurrentAssets"],
      namespace: "jppfs_cor",
    },
    current_liabilities: {
      elements: ["CurrentLiabilities"],
      namespace: "jppfs_cor",
    },
    noncurrent_liabilities: {
      elements: ["NoncurrentLiabilities"],
      namespace: "jppfs_cor",
    },
    shareholders_equity: {
      elements: ["ShareholdersEquity"],
      namespace: "jppfs_cor",
    },
  }.freeze

  # コンテキストIDのマッピング
  # XBRLでは同じ要素名でもコンテキストIDで期間（当期/前期）や連結/個別を区別する
  CONTEXT_PATTERNS = {
    consolidated_duration: /\ACurrentYearDuration\z/,
    consolidated_instant: /\ACurrentYearInstant\z/,
    non_consolidated_duration: /\ACurrentYearDuration_NonConsolidatedMember\z/,
    non_consolidated_instant: /\ACurrentYearInstant_NonConsolidatedMember\z/,
    prior_consolidated_duration: /\APrior1YearDuration\z/,
    prior_consolidated_instant: /\APrior1YearInstant\z/,
  }.freeze

  # P/L, C/F項目はduration（期間）コンテキスト、B/S項目はinstant（時点）コンテキスト
  DURATION_KEYS = %i[net_sales operating_income ordinary_income net_income
                     operating_cf investing_cf financing_cf
                     cost_of_sales gross_profit sga_expenses].freeze
  INSTANT_KEYS = %i[total_assets net_assets cash_and_equivalents
                    current_assets noncurrent_assets current_liabilities
                    noncurrent_liabilities shareholders_equity].freeze

  attr_reader :zip_path

  # @param zip_path [String] ダウンロードしたZIPファイルのパス
  def initialize(zip_path:)
    @zip_path = zip_path
  end

  # ZIPを展開しXBRLをパースして財務数値を抽出する
  #
  # @return [Hash] 抽出結果
  #   {
  #     consolidated: {
  #       net_sales: 1234567890,
  #       operating_income: 123456789,
  #       ...
  #       extended: { cost_of_sales: ..., gross_profit: ..., ... }
  #     },
  #     non_consolidated: { ... },  # 個別決算がない場合はnil
  #   }
  #
  def parse
    xbrl_content = load_xbrl_from_zip
    return nil unless xbrl_content

    doc = Nokogiri::XML(xbrl_content)
    register_namespaces(doc)

    {
      consolidated: extract_values(doc, scope: :consolidated),
      non_consolidated: extract_values(doc, scope: :non_consolidated),
    }
  end

  # ZIP内のXBRLインスタンスファイルを読み出す
  #
  # @return [String, nil] XBRLファイルの内容。見つからない場合nil
  def load_xbrl_from_zip
    Zip::File.open(zip_path) do |zip|
      entry = zip.glob("XBRL/PublicDoc/*.xbrl").first
      return entry&.get_input_stream&.read
    end
  end

  # 指定スコープ（連結/個別）の財務数値を抽出する
  #
  # @param doc [Nokogiri::XML::Document] パース済みXBRLドキュメント
  # @param scope [Symbol] :consolidated or :non_consolidated
  # @return [Hash, nil] 財務数値のHash。該当データがない場合nil
  def extract_values(doc, scope:)
    duration_context = get_context_pattern(scope, :duration)
    instant_context = get_context_pattern(scope, :instant)

    values = {}

    # 固定カラム対象の要素を抽出
    ELEMENT_MAPPING.each do |key, mapping|
      context = DURATION_KEYS.include?(key) ? duration_context : instant_context
      values[key] = find_element_value(doc, mapping, context)
    end

    # 拡張要素を抽出
    extended = {}
    EXTENDED_ELEMENT_MAPPING.each do |key, mapping|
      context = DURATION_KEYS.include?(key) ? duration_context : instant_context
      extended[key] = find_element_value(doc, mapping, context)
    end

    # 連結・個別の判定: 主要項目が1つも取得できなければnilを返す
    primary_keys = %i[net_sales operating_income total_assets]
    return nil if primary_keys.all? { |k| values[k].nil? }

    values[:extended] = extended.compact
    values.compact
  end

  # XBRL要素の値を検索して返す
  #
  # @param doc [Nokogiri::XML::Document]
  # @param mapping [Hash] { elements: [...], namespace: "..." }
  # @param context_pattern [Regexp] コンテキストIDのパターン
  # @return [Integer, nil] 抽出した数値。見つからない場合nil
  def find_element_value(doc, mapping, context_pattern)
    namespace = mapping[:namespace]
    mapping[:elements].each do |element_name|
      # 名前空間プレフィックス付きで要素を検索
      nodes = doc.xpath("//#{namespace}:#{element_name}")
      nodes.each do |node|
        context_ref = node.attr("contextRef")
        next unless context_ref&.match?(context_pattern)

        text = node.text.strip
        next if text.empty?

        return parse_numeric(text)
      end
    end
    nil
  end

  private

  def register_namespaces(doc)
    # XBRLファイルに宣言された名前空間を登録
    # jppfs_cor が宣言されていない場合はデフォルトURIを設定
    unless doc.namespaces.values.any? { |ns| ns.include?("jppfs_cor") }
      doc.root&.add_namespace("jppfs_cor", "http://disclosure.edinet-fsa.go.jp/taxonomy/jppfs/cor")
    end
  end

  def get_context_pattern(scope, type)
    case [scope, type]
    when [:consolidated, :duration]
      CONTEXT_PATTERNS[:consolidated_duration]
    when [:consolidated, :instant]
      CONTEXT_PATTERNS[:consolidated_instant]
    when [:non_consolidated, :duration]
      CONTEXT_PATTERNS[:non_consolidated_duration]
    when [:non_consolidated, :instant]
      CONTEXT_PATTERNS[:non_consolidated_instant]
    end
  end

  # XBRL数値テキストをIntegerに変換する
  # XBRLでは数値はテキストで表現され、マイナスは先頭に"-"が付く
  # decimalsやunitRefも考慮が必要だが、EDINETでは基本的に単位は円
  def parse_numeric(text)
    # カンマを除去し整数変換
    cleaned = text.gsub(",", "")
    Integer(cleaned)
  rescue ArgumentError
    # 小数の場合
    Float(cleaned).to_i rescue nil
  end
end
```

#### 依存gem: rubyzip

ZIPファイルの展開に `rubyzip` gemが必要。Gemfileに追加する。

```ruby
gem "rubyzip", require: "zip"
```

#### 設計判断

- **Nokogiriベースの自前実装**: 既存のRuby XBRL gem（litexbrl, xbrlware-ce等）はいずれもメンテナンスが停止しており、EDINET v2のタクソノミに対応していない。Nokogiriは活発にメンテナンスされており、プロジェクトのGemfileにも含まれている
- **要素名の候補配列**: 企業によって使用する勘定科目が異なる（例: 売上高は `NetSales` だが、銀行業では `OperatingRevenue1`）。候補を配列で定義し、先頭から順に検索することで対応
- **連結・個別の分離**: コンテキストIDの正規表現マッチで連結/個別を区別。主要3項目（売上高・営業利益・総資産）がすべてnilのスコープはnilを返す
- **命名規約**: `load_xbrl_from_zip` はファイルI/Oを伴うため `load_` プレフィックス。`parse`, `extract_values`, `find_element_value` は計算処理
- **`find_element_value` の公開**: テストしやすさを重視し、privateにしない（コーディング規約に準拠）

#### テスト: `spec/lib/edinet_xbrl_parser_spec.rb`

XBRLパーサーのテストは、テスト用のXBRLフィクスチャファイルを用いる。

```ruby
RSpec.describe EdinetXbrlParser do
  # テスト用XBRLフィクスチャの作成
  # spec/fixtures/edinet/ 配下にテスト用ZIPファイルを配置する

  describe "#parse" do
    context "テスト用XBRLフィクスチャが存在する場合" do
      let(:fixture_zip_path) { Rails.root.join("spec/fixtures/edinet/sample_xbrl.zip") }

      before do
        skip "XBRLフィクスチャが未配置" unless File.exist?(fixture_zip_path)
      end

      it "連結財務数値を抽出できる" do
        parser = EdinetXbrlParser.new(zip_path: fixture_zip_path.to_s)
        result = parser.parse

        expect(result).to have_key(:consolidated)
        consolidated = result[:consolidated]
        # 売上高・営業利益・総資産のいずれかが取得できていること
        expect(
          consolidated[:net_sales] || consolidated[:operating_income] || consolidated[:total_assets]
        ).not_to be_nil
      end
    end
  end

  describe "#find_element_value" do
    it "XBRLドキュメントから指定要素の値を抽出できる" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xbrli:xbrl
          xmlns:xbrli="http://www.xbrl.org/2003/instance"
          xmlns:jppfs_cor="http://disclosure.edinet-fsa.go.jp/taxonomy/jppfs/cor">
          <jppfs_cor:NetSales contextRef="CurrentYearDuration" unitRef="JPY" decimals="0">1234567890</jppfs_cor:NetSales>
          <jppfs_cor:Assets contextRef="CurrentYearInstant" unitRef="JPY" decimals="0">9876543210</jppfs_cor:Assets>
        </xbrli:xbrl>
      XML

      doc = Nokogiri::XML(xml)
      parser = EdinetXbrlParser.new(zip_path: "dummy")

      # P/L項目（duration context）
      mapping = { elements: ["NetSales"], namespace: "jppfs_cor" }
      value = parser.find_element_value(doc, mapping, /\ACurrentYearDuration\z/)
      expect(value).to eq(1_234_567_890)

      # B/S項目（instant context）
      mapping = { elements: ["Assets"], namespace: "jppfs_cor" }
      value = parser.find_element_value(doc, mapping, /\ACurrentYearInstant\z/)
      expect(value).to eq(9_876_543_210)
    end

    it "候補配列の先頭要素が見つからない場合、次の候補を検索する" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xbrli:xbrl
          xmlns:xbrli="http://www.xbrl.org/2003/instance"
          xmlns:jppfs_cor="http://disclosure.edinet-fsa.go.jp/taxonomy/jppfs/cor">
          <jppfs_cor:OperatingRevenue1 contextRef="CurrentYearDuration" unitRef="JPY" decimals="0">5000000000</jppfs_cor:OperatingRevenue1>
        </xbrli:xbrl>
      XML

      doc = Nokogiri::XML(xml)
      parser = EdinetXbrlParser.new(zip_path: "dummy")

      # NetSalesがない場合、OperatingRevenue1を検索
      mapping = { elements: ["NetSales", "OperatingRevenue1"], namespace: "jppfs_cor" }
      value = parser.find_element_value(doc, mapping, /\ACurrentYearDuration\z/)
      expect(value).to eq(5_000_000_000)
    end

    it "該当する要素がない場合nilを返す" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xbrli:xbrl xmlns:xbrli="http://www.xbrl.org/2003/instance">
        </xbrli:xbrl>
      XML

      doc = Nokogiri::XML(xml)
      parser = EdinetXbrlParser.new(zip_path: "dummy")

      mapping = { elements: ["NetSales"], namespace: "jppfs_cor" }
      value = parser.find_element_value(doc, mapping, /\ACurrentYearDuration\z/)
      expect(value).to be_nil
    end
  end

  describe "#extract_values" do
    it "主要3項目がすべてnilの場合nilを返す" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xbrli:xbrl xmlns:xbrli="http://www.xbrl.org/2003/instance">
        </xbrli:xbrl>
      XML

      doc = Nokogiri::XML(xml)
      parser = EdinetXbrlParser.new(zip_path: "dummy")

      result = parser.extract_values(doc, scope: :consolidated)
      expect(result).to be_nil
    end
  end
end
```

---

### タスク3: Gemfileへの rubyzip 追加

```ruby
# Gemfile に追加
gem "rubyzip", require: "zip"
```

`bundle install` を実行し、`Gemfile.lock` を更新する。

---

### タスク4: テスト用フィクスチャの準備

#### ディレクトリ: `spec/fixtures/edinet/`

テスト用のXBRLフィクスチャを配置するディレクトリを作成する。

実際のEDINET書類からダウンロードしたZIPファイルをテスト用に配置できるが、サイズが大きいため `.gitignore` に追加し、CIではXBRLフィクスチャ依存のテストをスキップする方針とする。

```
# .gitignore に追加
spec/fixtures/edinet/*.zip
```

`find_element_value` など単体メソッドのテストは、インラインXMLで記述するためフィクスチャ不要。

---

## データフローの概要

以下は本タスクで実装するクライアント・パーサーが、今後のデータ取り込みパイプライン（別TODO）でどう使われるかの概要。

```
1. EdinetApi#load_target_documents(date:)
   → 指定日の対象書類一覧を取得（JSON）

2. 各書類について:
   EdinetApi#load_xbrl_zip(doc_id:)
   → XBRLのZIPファイルをダウンロード（Tempfile）

3. EdinetXbrlParser#parse
   → ZIPを展開 → XBRLをNokogiriでパース → 財務数値を抽出

4. 抽出結果をDBに保存（データ取り込みパイプラインの責務）:
   → FinancialReport レコード作成
   → FinancialValue レコード作成（固定カラム + data_json）
```

---

## XBRL要素名とfinancial_valuesカラムの対応表

| financial_values カラム | XBRL要素名（jppfs_cor） | コンテキスト種別 |
|---|---|---|
| net_sales | NetSales / OperatingRevenue1 / Revenue1 | duration |
| operating_income | OperatingIncome / OperatingProfit | duration |
| ordinary_income | OrdinaryIncome / OrdinaryProfit | duration |
| net_income | ProfitLossAttributableToOwnersOfParent / ProfitLoss / NetIncome | duration |
| total_assets | Assets | instant |
| net_assets | NetAssets | instant |
| operating_cf | NetCashProvidedByUsedInOperatingActivities | duration |
| investing_cf | NetCashProvidedByUsedInInvestmentActivities | duration |
| financing_cf | NetCashProvidedByUsedInFinancingActivities | duration |
| cash_and_equivalents | CashAndCashEquivalentsAtEndOfPeriod / CashAndCashEquivalents | instant |

拡張要素（data_json格納）:

| data_json キー | XBRL要素名（jppfs_cor） | コンテキスト種別 |
|---|---|---|
| cost_of_sales | CostOfSales | duration |
| gross_profit | GrossProfit | duration |
| sga_expenses | SellingGeneralAndAdministrativeExpenses | duration |
| current_assets | CurrentAssets | instant |
| noncurrent_assets | NoncurrentAssets | instant |
| current_liabilities | CurrentLiabilities | instant |
| noncurrent_liabilities | NoncurrentLiabilities | instant |
| shareholders_equity | ShareholdersEquity | instant |

注意: EPS, BPS, equity_ratio, shares_outstanding, treasury_shares はXBRL本表からの直接抽出が困難な場合がある（経営指標セクション `jpcrp_cor` に記載されることが多い）。これらはJQUANTS APIからの取得をメインとし、EDINET XBRLからの取得は将来的な拡張とする。

---

## 実装順序

1. Gemfileに `rubyzip` 追加 → `bundle install`
2. `app/lib/edinet_api.rb` 実装
3. `spec/lib/edinet_api_spec.rb` 実装・テスト実行
4. `app/lib/edinet_xbrl_parser.rb` 実装
5. `spec/lib/edinet_xbrl_parser_spec.rb` 実装・テスト実行
6. `spec/fixtures/edinet/` ディレクトリ作成・`.gitignore` 更新
