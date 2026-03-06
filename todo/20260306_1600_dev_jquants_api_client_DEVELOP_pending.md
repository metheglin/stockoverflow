# JQUANTS APIクライアント実装

## 概要

J-Quants API v2 を利用して上場銘柄一覧・株価四本値・財務情報サマリーを取得するためのAPIクライアントを実装する。

`app/lib/` に配置し、コーディング規約の「汎用性と利便性」の方針に従って設計する。

## 前提知識

### J-Quants API v2

- ベースURL: `https://api.jquants.com/v2/`
- 認証: リクエストヘッダー `x-api-key` にAPIキーを指定
- APIキー: `Rails.application.credentials.jquants.api_key`
  - V2ではトークンリフレッシュ不要。APIキーは有効期限なし（ダッシュボードから再発行・削除可能）
- レスポンス形式: 全エンドポイント共通で `{ "data": [...], "pagination_key": "..." }`
- ページネーション: レスポンスに `pagination_key` が含まれる場合、次のリクエストでクエリパラメータとして渡すことで続きを取得

### レート制限（リクエスト/分）

| プラン | リクエスト/分 |
|--------|-------------|
| Free | 5 |
| Light | 60 |
| Standard | 120 |
| Premium | 500 |

### 主要エンドポイント

| データ種別 | V2エンドポイント | プラン |
|-----------|----------------|--------|
| 上場銘柄一覧 | `GET /v2/equities/master` | Free〜 |
| 株価四本値 | `GET /v2/equities/bars/daily` | Free〜 |
| 財務情報サマリー | `GET /v2/fins/summary` | Free〜 |
| 配当情報 | `GET /v2/fins/dividend` | Free〜 |
| 決算発表日 | `GET /v2/equities/earnings-calendar` | Free〜 |

### V2 レスポンスフィールド名（省略形）

V2では多くのフィールド名がV1から省略形に変更されている。

#### 上場銘柄一覧 `/v2/equities/master`

| V2フィールド | 説明 | companiesカラム |
|-------------|------|----------------|
| `Date` | 適用日 | - |
| `Code` | 証券コード（5桁） | `securities_code` |
| `CoName` | 企業名（日本語） | `name` |
| `CoNameEn` | 企業名（英語） | `name_english` |
| `S17` | 17業種コード | `sector_17_code` |
| `S17Nm` | 17業種名 | `sector_17_name` |
| `S33` | 33業種コード | `sector_33_code` |
| `S33Nm` | 33業種名 | `sector_33_name` |
| `ScaleCat` | TOPIXスケール区分 | `scale_category` |
| `Mkt` | 市場コード | `market_code` |
| `MktNm` | 市場名 | `market_name` |
| `Mrgn` | 信用区分コード | (data_json) |
| `MrgnNm` | 信用区分名 | (data_json) |

#### 株価四本値 `/v2/equities/bars/daily`

| V2フィールド | 説明 | daily_quotesカラム |
|-------------|------|-------------------|
| `Date` | 取引日 | `traded_on` |
| `Code` | 証券コード | (company_id経由) |
| `O` | 始値 | `open_price` |
| `H` | 高値 | `high_price` |
| `L` | 安値 | `low_price` |
| `C` | 終値 | `close_price` |
| `Vo` | 出来高 | `volume` |
| `Va` | 売買代金 | `turnover_value` |
| `AdjFactor` | 調整係数 | `adjustment_factor` |
| `AdjO` | 調整済始値 | (data_json) |
| `AdjH` | 調整済高値 | (data_json) |
| `AdjL` | 調整済安値 | (data_json) |
| `AdjC` | 調整済終値 | `adjusted_close` |
| `AdjVo` | 調整済出来高 | (data_json) |

#### 財務情報サマリー `/v2/fins/summary`

| V2フィールド | 説明 | DB対応先 |
|-------------|------|----------|
| `DiscDate` | 開示日 | `financial_reports.disclosed_at` |
| `DiscTime` | 開示時刻 | (data_json) |
| `Code` | 証券コード | (company_id経由) |
| `DiscNo` | 開示番号 | (data_json) |
| `DocType` | 書類種別 | `financial_reports.doc_type_code` |
| `CurPerType` | 当期種別(FY/1Q/2Q/3Q) | `financial_reports.report_type` |
| `CurPerSt` | 当期開始日 | `financial_reports.period_start` |
| `CurPerEn` | 当期終了日 | `financial_reports.period_end` |
| `CurFYSt` | 会計年度開始日 | `financial_reports.fiscal_year_start` |
| `CurFYEn` | 会計年度終了日 | `financial_reports.fiscal_year_end` |
| `Sales` | 売上高 | `financial_values.net_sales` |
| `OP` | 営業利益 | `financial_values.operating_income` |
| `OdP` | 経常利益 | `financial_values.ordinary_income` |
| `NP` | 純利益 | `financial_values.net_income` |
| `EPS` | 1株当たり利益 | `financial_values.eps` |
| `DEPS` | 希薄化後EPS | `financial_values.diluted_eps` |
| `TA` | 総資産 | `financial_values.total_assets` |
| `Eq` | 純資産 | `financial_values.net_assets` |
| `EqRatio` | 自己資本比率 | `financial_values.equity_ratio` |
| `BPS` | 1株当たり純資産 | `financial_values.bps` |
| `CFO` | 営業CF | `financial_values.operating_cf` |
| `CFI` | 投資CF | `financial_values.investing_cf` |
| `CFF` | 財務CF | `financial_values.financing_cf` |
| `CashEq` | 現金同等物 | `financial_values.cash_and_equivalents` |
| `ShOutFY` | 発行済株式数 | `financial_values.shares_outstanding` |
| `TrShFY` | 自己株式数 | `financial_values.treasury_shares` |
| `AvgSh` | 平均株式数 | (data_json) |
| `DivAnn` | 年間配当実績 | (data_json: dividend_per_share_annual) |
| `FDivAnn` | 年間配当予想 | (data_json) |
| `FSales` | 売上高予想 | (data_json: forecast_net_sales) |
| `FOP` | 営業利益予想 | (data_json: forecast_operating_income) |
| `FOdP` | 経常利益予想 | (data_json: forecast_ordinary_income) |
| `FNP` | 純利益予想 | (data_json: forecast_net_income) |
| `FEPS` | EPS予想 | (data_json: forecast_eps) |
| `NCSales` | 個別売上高 | (non_consolidated用) |
| `NCOP` | 個別営業利益 | (non_consolidated用) |
| `NCOdP` | 個別経常利益 | (non_consolidated用) |
| `NCNP` | 個別純利益 | (non_consolidated用) |
| `NCEPS` | 個別EPS | (non_consolidated用) |
| `NCTA` | 個別総資産 | (non_consolidated用) |
| `NCEq` | 個別純資産 | (non_consolidated用) |
| `NCBPS` | 個別BPS | (non_consolidated用) |

#### report_type 変換ルール（CurPerType → report_type）

| CurPerType | report_type |
|-----------|-------------|
| `FY` | `annual` (0) |
| `1Q` | `q1` (1) |
| `2Q` | `q2` (2) |
| `3Q` | `q3` (3) |

---

## 実装タスク

### タスク1: JquantsApi クライアント

#### ファイル: `app/lib/jquants_api.rb`

J-Quants API v2へのHTTPリクエストを担うクライアント。Faradayを使用する。

```ruby
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
      conn.request :retry, max: 2, interval: 3, backoff_factor: 2
      conn.response :raise_error
      conn.adapter Faraday.default_adapter
    end
  end

  def get(path, params = {})
    @connection.get(path, params)
  end

  # 日付文字列をAPIが受け付ける形式に正規化する
  # Date型はYYYYMMDD形式に変換、ハイフン付き文字列はそのまま許容
  def format_date(date)
    return nil unless date
    if date.is_a?(Date)
      date.strftime("%Y-%m-%d")
    else
      date.to_s
    end
  end
end
```

#### 設計判断

- **コーディング規約「汎用性と利便性」準拠**: `api_key` をコンストラクタ引数で受け取り、`JquantsApi.default` 便利メソッドでcredentialsからの取得を提供
- **V2 API対応**: V1のトークンリフレッシュ方式ではなく、V2の `x-api-key` ヘッダー方式を採用。トークン管理が不要でシンプル
- **ページネーション自動処理**: `load_all_pages` メソッドで `pagination_key` を自動追跡し、全ページを結合して返す。呼び出し元はページネーションを意識しなくてよい
- **エラーハンドリング**: `Faraday::Response::RaiseError` を使い、4xx/5xxレスポンスでFaradayの例外を発生させる。エラーハンドリング規約に従い、クライアント側では例外を捕捉せず呼び出し元に委ねる
- **リトライ**: `faraday-retry` gemを活用。ネットワーク一時障害やサーバーエラー時に自動リトライ（最大2回、3秒間隔、バックオフ2倍）
- **命名規約**: 全メソッドはAPI呼び出しを伴うため `load_` プレフィックス
- **`load_all_pages` の公開**: テストしやすさを重視し、privateにしない（コーディング規約に準拠）
- **EdinetApiとの一貫性**: 同じFaradayベースの構成、同じ便利メソッドパターン、同じリトライ設定を採用し、プロジェクト全体のコードの統一感を維持

#### テスト: `spec/lib/jquants_api_spec.rb`

テスティング規約に従い、APIKEYが指定されている場合は実際のAPI呼び出しテストを記述する。ただし影響が限定的な読み取り系のみ。
また、Faraday::Adapter::Test::Stubs を使ったユニットテストも記述し、APIキー未設定環境でもテスト可能にする。

```ruby
RSpec.describe JquantsApi do
  describe "Faradayスタブによるユニットテスト" do
    let(:api_key) { "test_api_key" }
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:client) do
      client = JquantsApi.new(api_key: api_key)
      # テスト用にconnectionを差し替え
      test_connection = Faraday.new(url: JquantsApi::BASE_URL) do |conn|
        conn.headers["x-api-key"] = api_key
        conn.adapter :test, stubs
      end
      client.instance_variable_set(:@connection, test_connection)
      client
    end

    after { stubs.verify_stubbed_calls }

    describe "#load_listed_info" do
      it "上場銘柄一覧を取得できる" do
        response_body = {
          "data" => [
            { "Code" => "86970", "CoName" => "日本取引所グループ" }
          ]
        }.to_json

        stubs.get("equities/master") do |env|
          expect(env.request_headers["x-api-key"]).to eq(api_key)
          [200, { "Content-Type" => "application/json" }, response_body]
        end

        result = client.load_listed_info
        expect(result).to be_an(Array)
        expect(result.first["Code"]).to eq("86970")
      end

      it "codeパラメータを指定できる" do
        response_body = { "data" => [{ "Code" => "72030" }] }.to_json

        stubs.get("equities/master") do |env|
          expect(env.params["code"]).to eq("72030")
          [200, { "Content-Type" => "application/json" }, response_body]
        end

        result = client.load_listed_info(code: "72030")
        expect(result.first["Code"]).to eq("72030")
      end
    end

    describe "#load_daily_quotes" do
      it "株価四本値を取得できる" do
        response_body = {
          "data" => [
            { "Date" => "2024-01-15", "Code" => "72030", "O" => 2500.0, "C" => 2520.0 }
          ]
        }.to_json

        stubs.get("equities/bars/daily") do |env|
          expect(env.params["code"]).to eq("72030")
          expect(env.params["from"]).to eq("20240101")
          expect(env.params["to"]).to eq("20240131")
          [200, { "Content-Type" => "application/json" }, response_body]
        end

        result = client.load_daily_quotes(code: "72030", from: "20240101", to: "20240131")
        expect(result).to be_an(Array)
        expect(result.first["O"]).to eq(2500.0)
      end
    end

    describe "#load_financial_statements" do
      it "財務情報サマリーを取得できる" do
        response_body = {
          "data" => [
            { "Code" => "86970", "Sales" => "100529000000", "CurPerType" => "3Q" }
          ]
        }.to_json

        stubs.get("fins/summary") do |env|
          expect(env.params["code"]).to eq("86970")
          [200, { "Content-Type" => "application/json" }, response_body]
        end

        result = client.load_financial_statements(code: "86970")
        expect(result.first["Sales"]).to eq("100529000000")
      end
    end

    describe "#load_earnings_calendar" do
      it "決算発表予定日を取得できる" do
        response_body = {
          "data" => [
            { "Code" => "86970", "Date" => "2024-04-30" }
          ]
        }.to_json

        stubs.get("equities/earnings-calendar") do |env|
          [200, { "Content-Type" => "application/json" }, response_body]
        end

        result = client.load_earnings_calendar(date: "20240430")
        expect(result).to be_an(Array)
        expect(result.first["Code"]).to eq("86970")
      end
    end

    describe "#load_all_pages" do
      it "ページネーションを自動処理して全データを結合する" do
        page1_body = {
          "data" => [{ "Code" => "10000" }],
          "pagination_key" => "next_page_key"
        }.to_json

        page2_body = {
          "data" => [{ "Code" => "20000" }]
        }.to_json

        call_count = 0
        stubs.get("equities/master") do |env|
          call_count += 1
          if call_count == 1
            expect(env.params).not_to have_key("pagination_key")
            [200, { "Content-Type" => "application/json" }, page1_body]
          else
            expect(env.params["pagination_key"]).to eq("next_page_key")
            [200, { "Content-Type" => "application/json" }, page2_body]
          end
        end

        result = client.load_all_pages("equities/master")
        expect(result.length).to eq(2)
        expect(result.map { |r| r["Code"] }).to eq(["10000", "20000"])
      end

      it "pagination_keyがない場合は1ページで終了する" do
        response_body = { "data" => [{ "Code" => "10000" }] }.to_json

        stubs.get("equities/master") do
          [200, { "Content-Type" => "application/json" }, response_body]
        end

        result = client.load_all_pages("equities/master")
        expect(result.length).to eq(1)
      end
    end

    describe ".default" do
      it "credentialsのAPIキーでインスタンスを生成できる" do
        skip "credentials not configured" unless Rails.application.credentials.dig(:jquants, :api_key)
        client = JquantsApi.default
        expect(client.api_key).to eq(Rails.application.credentials.jquants.api_key)
      end
    end
  end

  describe "実API呼び出しテスト" do
    let(:api_key) do
      ENV["JQUANTS_API_KEY"] || Rails.application.credentials.dig(:jquants, :api_key)
    end

    before do
      skip "JQUANTS API key not configured" unless api_key
    end

    describe "#load_listed_info" do
      it "上場銘柄一覧を取得できる" do
        client = JquantsApi.new(api_key: api_key)
        result = client.load_listed_info(code: "86970")

        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first).to have_key("Code")
        expect(result.first).to have_key("CoName")
      end
    end

    describe "#load_daily_quotes" do
      it "株価四本値を取得できる" do
        client = JquantsApi.new(api_key: api_key)
        result = client.load_daily_quotes(code: "86970", from: "20240101", to: "20240110")

        expect(result).to be_an(Array)
        result.each do |quote|
          expect(quote).to have_key("Date")
          expect(quote).to have_key("C")
        end
      end
    end

    describe "#load_financial_statements" do
      it "財務情報サマリーを取得できる" do
        client = JquantsApi.new(api_key: api_key)
        result = client.load_financial_statements(code: "86970")

        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first).to have_key("Code")
        expect(result.first).to have_key("CurPerType")
      end
    end
  end
end
```

---

### タスク2: EDINETとのデータ連携設計

#### 企業の紐づけ方法

EDINETコードと証券コードは異なる体系であり、同一企業を紐づけるために `companies` テーブルの両カラムを使用する。

| 項目 | EDINET | JQUANTS |
|------|--------|---------|
| 企業識別子 | `edinet_code` (E+5桁数字) | `securities_code` (5桁数字) |
| 格納先カラム | `companies.edinet_code` | `companies.securities_code` |
| ユニーク制約 | あり | あり |

紐づけ方法:
1. JQUANTS の上場銘柄一覧を先に取り込み、`securities_code` で企業マスターを作成
2. EDINET の書類一覧から `secCode` (証券コード) を取得し、`securities_code` で既存企業にマッチング
3. マッチした企業に `edinet_code` を設定
4. 証券コードがない場合（非上場企業等）は `edinet_code` のみで企業を作成

#### データ重複の扱い

両APIから取得可能な財務データの優先度:

| データ項目 | 優先ソース | 理由 |
|-----------|-----------|------|
| 売上高・営業利益・経常利益・純利益 | JQUANTS | 構造化済みで扱いやすい |
| EPS・BPS・自己資本比率 | JQUANTS | XBRLからの直接抽出が困難 |
| 発行済株式数・自己株式数 | JQUANTS | 構造化済み |
| 詳細B/S項目 (流動資産・固定資産等) | EDINET | XBRL拡張要素でのみ取得可能 |
| CF詳細 | JQUANTS(v2で追加) | 構造化済み |
| 業績予想 | JQUANTS | 構造化済み |
| 配当実績・予想 | JQUANTS | 構造化済み |

基本方針:
- `financial_reports.source` で取得元を記録（`edinet: 0`, `jquants: 1`）
- 同一企業・同一決算期に対し、JQUANTS データを先に取り込み、EDINET XBRLから得られる追加データ（拡張B/S項目等）で補完する
- `financial_values` のユニーク制約 `(company_id, fiscal_year_end, scope, period_type)` により、同一決算期のデータは1レコードにまとめられる

---

## 実装順序

1. `app/lib/jquants_api.rb` 実装
2. `spec/lib/jquants_api_spec.rb` 実装・テスト実行

---

## EdinetApiとの設計比較

| 項目 | EdinetApi | JquantsApi |
|------|-----------|------------|
| BASE_URL | `https://api.edinet-fsa.go.jp/api/v2/` | `https://api.jquants.com/v2/` |
| 認証方式 | クエリパラメータ `Subscription-Key` | ヘッダー `x-api-key` |
| レスポンス形式 | エンドポイントごとに異なる | 統一 `{ "data": [...], "pagination_key": "..." }` |
| ページネーション | なし | `pagination_key` による自動ページング |
| 便利メソッド | `EdinetApi.default` | `JquantsApi.default` |
| リトライ | Faraday retry (max: 2, interval: 3s) | 同一設定 |
| データ形式 | XBRL (ZIP) → 要パース | JSON → そのまま利用可 |
