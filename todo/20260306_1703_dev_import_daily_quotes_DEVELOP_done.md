# 株価データ取り込みジョブ実装

## 概要

JQUANTS の株価四本値API (`/v2/equities/bars/daily`) から日次株価データを取得し、`daily_quotes` テーブルに保存するジョブを実装する。
バリュエーション指標（PER/PBR/PSR）の算出に必要な株価データの蓄積が主目的。

## 前提知識

### JQUANTS 株価四本値 `/v2/equities/bars/daily`

`JquantsApi#load_daily_quotes` で取得可能。

取得モード:
- **銘柄+期間指定**: `load_daily_quotes(code: "86970", from: "20240101", to: "20240131")` → その銘柄の指定期間の株価
- **日付指定**: `load_daily_quotes(date: "20240115")` → その日の全銘柄の株価

### V2 フィールド → DB カラム マッピング

| V2フィールド | 型 | DB先 | 変換処理 |
|-------------|-----|------|---------|
| `Date` | String | `traded_on` | Date.parse |
| `Code` | String | `company_id` | securities_code → Company検索 |
| `O` | Float | `open_price` | そのまま |
| `H` | Float | `high_price` | そのまま |
| `L` | Float | `low_price` | そのまま |
| `C` | Float | `close_price` | そのまま |
| `Vo` | Float | `volume` | to_i |
| `Va` | Float | `turnover_value` | to_i |
| `AdjFactor` | Float | `adjustment_factor` | そのまま |
| `AdjC` | Float | `adjusted_close` | そのまま |
| `AdjO` | Float | `data_json.adjusted_open` | data_jsonに格納 |
| `AdjH` | Float | `data_json.adjusted_high` | data_jsonに格納 |
| `AdjL` | Float | `data_json.adjusted_low` | data_jsonに格納 |
| `AdjVo` | Float | `data_json.adjusted_volume` | data_jsonに格納 |

### 実行頻度・運用

- **実行頻度**: 日次（営業日翌日の早朝。JQUANTS は翌営業日の朝にデータが反映される）
- **差分更新**: 最終取得日から当日までを日付指定モードで取得
- **初回全件取得**: `full: true` で全上場企業の過去データを銘柄指定で取得（大量データ注意）
- **レート制限**: JQUANTS のプランに応じたリクエスト/分の制限あり（Free=5req/min）。銘柄指定の全件取得時は `sleep` を挟む

### エラーハンドリング

- API呼び出し自体の失敗（ネットワーク障害等）は個別銘柄・個別日付の場合ログに記録して継続
- 個別レコードのDB保存失敗時もログに記録して継続

---

## 実装タスク

### タスク1: DailyQuote モデルへのフィールドマッピング定数追加

#### ファイル: `app/models/daily_quote.rb`

```ruby
class DailyQuote < ApplicationRecord
  # JQUANTS V2 bars/daily → daily_quotes 固定カラム マッピング
  JQUANTS_FIELD_MAP = {
    "O"         => :open_price,
    "H"         => :high_price,
    "L"         => :low_price,
    "C"         => :close_price,
    "Vo"        => :volume,
    "Va"        => :turnover_value,
    "AdjFactor" => :adjustment_factor,
    "AdjC"      => :adjusted_close,
  }.freeze

  # JQUANTS V2 bars/daily → daily_quotes data_json マッピング
  JQUANTS_DATA_JSON_FIELDS = %w[AdjO AdjH AdjL AdjVo].freeze

  # 整数として扱うカラム
  INTEGER_COLUMNS = %i[volume turnover_value].freeze

  belongs_to :company

  # JQUANTS V2 bars/daily のレスポンスデータから属性Hashを生成する
  #
  # @param data [Hash] JQUANTSレスポンスの1件分のHash
  # @return [Hash] DailyQuote.create / update に渡せる属性Hash
  #
  # 例:
  #   attrs = DailyQuote.get_attributes_from_jquants(data)
  #   # => { open_price: 2047.0, high_price: 2069.0, ... }
  #
  def self.get_attributes_from_jquants(data)
    attrs = {}
    JQUANTS_FIELD_MAP.each do |jquants_key, column|
      raw_value = data[jquants_key]
      next if raw_value.nil?

      attrs[column] = INTEGER_COLUMNS.include?(column) ? raw_value.to_i : raw_value
    end

    # data_json に格納するフィールド
    json_data = {}
    JQUANTS_DATA_JSON_FIELDS.each do |key|
      json_data[key.underscore] = data[key] if data[key].present?
    end
    attrs[:data_json] = json_data if json_data.any?

    attrs
  end
end
```

### タスク2: ImportDailyQuotesJob の実装

#### ファイル: `app/jobs/import_daily_quotes_job.rb`

```ruby
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
```

### タスク3: テスト

#### ファイル: `spec/models/daily_quote_spec.rb`

```ruby
RSpec.describe DailyQuote do
  describe ".get_attributes_from_jquants" do
    let(:jquants_data) do
      {
        "Date" => "2024-01-15",
        "Code" => "86970",
        "O" => 2047.0,
        "H" => 2069.0,
        "L" => 2035.0,
        "C" => 2045.0,
        "Vo" => 2202500.0,
        "Va" => 4507051850.0,
        "AdjFactor" => 1.0,
        "AdjO" => 2047.0,
        "AdjH" => 2069.0,
        "AdjL" => 2035.0,
        "AdjC" => 2045.0,
        "AdjVo" => 2202500.0,
      }
    end

    it "固定カラムの属性が正しく変換される" do
      attrs = DailyQuote.get_attributes_from_jquants(jquants_data)

      expect(attrs[:open_price]).to eq(2047.0)
      expect(attrs[:high_price]).to eq(2069.0)
      expect(attrs[:low_price]).to eq(2035.0)
      expect(attrs[:close_price]).to eq(2045.0)
      expect(attrs[:volume]).to eq(2202500)
      expect(attrs[:turnover_value]).to eq(4507051850)
      expect(attrs[:adjustment_factor]).to eq(1.0)
      expect(attrs[:adjusted_close]).to eq(2045.0)
    end

    it "data_jsonフィールドが正しく設定される" do
      attrs = DailyQuote.get_attributes_from_jquants(jquants_data)

      expect(attrs[:data_json]).to include(
        "adj_o" => 2047.0,
        "adj_h" => 2069.0,
        "adj_l" => 2035.0,
        "adj_vo" => 2202500.0,
      )
    end

    it "volume, turnover_valueは整数に変換される" do
      attrs = DailyQuote.get_attributes_from_jquants(jquants_data)

      expect(attrs[:volume]).to be_a(Integer)
      expect(attrs[:turnover_value]).to be_a(Integer)
    end

    it "nilの値はスキップされる" do
      data = { "O" => nil, "C" => 2045.0 }
      attrs = DailyQuote.get_attributes_from_jquants(data)

      expect(attrs).not_to have_key(:open_price)
      expect(attrs[:close_price]).to eq(2045.0)
    end
  end
end
```

---

## 設計判断

### 差分取得 vs 全件取得

- **日次運用**: 日付指定モードが効率的。1リクエストで全銘柄の1日分が取得できる
- **初回データ蓄積**: 銘柄指定モードで過去データを一括取得。レート制限に注意して `sleep` を挟む

### 土日スキップ

差分取得モードでは土日を自動スキップする。祝日はスキップしない（JQUANTS APIが空配列を返すだけで問題ない）。

### application_properties の共有

株価データとJQUANTS財務データは同じ `jquants_sync` レコードの `last_synced_date` を共有する。
両方のジョブが日次で実行される想定のため、同期日の管理を共有しても問題ない。
将来的に分離が必要になった場合、`ApplicationProperty` の `kind` に新しい値を追加する。

---

## 実装順序

1. `app/models/daily_quote.rb` に定数とクラスメソッドを追加
2. `app/jobs/import_daily_quotes_job.rb` を新規作成
3. `spec/models/daily_quote_spec.rb` を新規作成・テスト実行
