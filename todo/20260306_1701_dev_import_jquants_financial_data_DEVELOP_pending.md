# JQUANTS 決算データ取り込みジョブ実装

## 概要

JQUANTS の財務情報サマリーAPI (`/v2/fins/summary`) から決算データを取得し、`financial_reports` / `financial_values` テーブルに保存するジョブを実装する。

JQUANTS は構造化済みデータを提供するため、本ジョブが財務データの主要ソースとなる。
EDINET XBRLからの取り込みは補完的な位置づけであり、別ジョブ（`ImportEdinetDocumentsJob`）で対応する。

## 前提知識

### JQUANTS 財務情報サマリー `/v2/fins/summary`

`JquantsApi#load_financial_statements` で取得可能。

取得モード:
- **銘柄指定**: `load_financial_statements(code: "86970")` → その銘柄の全期間の決算データ
- **日付指定**: `load_financial_statements(date: "20240130")` → その日に開示された全銘柄の決算データ

### V2 フィールド → DB カラム マッピング

#### financial_reports カラム

| V2フィールド | 型 | DB先 | 変換処理 |
|-------------|-----|------|---------|
| `DiscDate` | String | `disclosed_at` | Date.parse |
| `Code` | String | `company_id` | securities_code → Company検索 |
| `DocType` | String | `doc_type_code` | そのまま |
| `CurPerType` | String | `report_type` | `PERIOD_TYPE_MAP` で変換 (`FY`→annual, `1Q`→q1, `2Q`→q2, `3Q`→q3) |
| `CurPerSt` | String | `period_start` | Date.parse |
| `CurPerEn` | String | `period_end` | Date.parse |
| `CurFYSt` | String | `fiscal_year_start` | Date.parse |
| `CurFYEn` | String | `fiscal_year_end` | Date.parse |
| - | - | `source` | `jquants` (1) 固定 |

#### financial_values カラム（連結: scope=consolidated）

| V2フィールド | 型 | DB先 | 変換処理 |
|-------------|-----|------|---------|
| `Sales` | String | `net_sales` | to_i（空文字列はnil） |
| `OP` | String | `operating_income` | to_i |
| `OdP` | String | `ordinary_income` | to_i |
| `NP` | String | `net_income` | to_i |
| `EPS` | String | `eps` | to_d |
| `DEPS` | String | `diluted_eps` | to_d |
| `TA` | String | `total_assets` | to_i |
| `Eq` | String | `net_assets` | to_i |
| `EqRatio` | String | `equity_ratio` | to_d |
| `BPS` | String | `bps` | to_d |
| `CFO` | String | `operating_cf` | to_i |
| `CFI` | String | `investing_cf` | to_i |
| `CFF` | String | `financing_cf` | to_i |
| `CashEq` | String | `cash_and_equivalents` | to_i |
| `ShOutFY` | String | `shares_outstanding` | to_i |
| `TrShFY` | String | `treasury_shares` | to_i |

#### financial_values data_json（連結）

| V2フィールド | DB先 (data_json key) |
|-------------|---------------------|
| `DivAnn` | `dividend_per_share_annual` |
| `FSales` | `forecast_net_sales` |
| `FOP` | `forecast_operating_income` |
| `FOdP` | `forecast_ordinary_income` |
| `FNP` | `forecast_net_income` |
| `FEPS` | `forecast_eps` |

#### financial_values カラム（個別: scope=non_consolidated）

個別決算データは V2 フィールド名に `NC` プレフィックスがつく。

| V2フィールド | DB先 |
|-------------|------|
| `NCSales` | `net_sales` |
| `NCOP` | `operating_income` |
| `NCOdP` | `ordinary_income` |
| `NCNP` | `net_income` |
| `NCEPS` | `eps` |
| `NCTA` | `total_assets` |
| `NCEq` | `net_assets` |
| `NCBPS` | `bps` |

個別決算データは連結の主要フィールドのみ。CF・予想等は含まれない。

### 実行頻度・運用

- **実行頻度**: 日次
- **差分更新モード**: `application_properties` (kind: `jquants_sync`) の `last_synced_date` を基準に、日付指定APIで未取得日分のデータを取得
- **全件更新モード**: 引数で `full: true` を指定した場合、全上場企業について銘柄指定APIで取得
- **最終同期日**: `application_properties` (kind: `jquants_sync`) の `last_synced_date` に記録

### エラーハンドリング

- API呼び出し自体の失敗（ネットワーク障害等）は例外をそのまま伝播
- 個別企業・個別決算のDB保存失敗時はログに記録して次のレコードへ継続
- 全件更新モードで個別銘柄のAPI呼び出しが失敗した場合もログに記録して継続

### ユニーク制約

- `financial_reports`: `doc_id` のユニークインデックス。JQUANTS由来のデータには EDINET doc_id がないため、JQUANTS由来と判別できる一意なキーを `doc_id` に設定する（後述）
- `financial_values`: `(company_id, fiscal_year_end, scope, period_type)` のユニーク制約。同一企業・同一決算期・同一スコープ・同一期間のデータは1レコードにまとめる

### JQUANTS由来 financial_reports の doc_id 生成ルール

JQUANTSレスポンスには EDINET の `docID` に相当する一意な識別子がない。
`DiscNo`（開示番号）が存在するが、全ての決算に付与されているわけではない。
そのため、以下のルールで `doc_id` を合成する:

```
doc_id = "JQ_#{Code}_#{CurFYEn}_#{CurPerType}"
```

例: `JQ_86970_2024-03-31_FY`

これにより JQUANTS 由来のレコードを一意に識別でき、EDINET 由来のレコード（`S100XXXX` 形式）と衝突しない。

---

## 実装タスク

### タスク1: FinancialValue モデルへのフィールドマッピング定数追加

#### ファイル: `app/models/financial_value.rb`

```ruby
class FinancialValue < ApplicationRecord
  include JsonAttribute

  # JQUANTS V2 fins/summary → financial_values 固定カラム マッピング（連結）
  JQUANTS_CONSOLIDATED_FIELD_MAP = {
    "Sales"    => :net_sales,
    "OP"       => :operating_income,
    "OdP"      => :ordinary_income,
    "NP"       => :net_income,
    "EPS"      => :eps,
    "DEPS"     => :diluted_eps,
    "TA"       => :total_assets,
    "Eq"       => :net_assets,
    "EqRatio"  => :equity_ratio,
    "BPS"      => :bps,
    "CFO"      => :operating_cf,
    "CFI"      => :investing_cf,
    "CFF"      => :financing_cf,
    "CashEq"   => :cash_and_equivalents,
    "ShOutFY"  => :shares_outstanding,
    "TrShFY"   => :treasury_shares,
  }.freeze

  # JQUANTS V2 fins/summary → financial_values data_json マッピング（連結）
  JQUANTS_CONSOLIDATED_DATA_JSON_MAP = {
    "DivAnn" => "dividend_per_share_annual",
    "FSales" => "forecast_net_sales",
    "FOP"    => "forecast_operating_income",
    "FOdP"   => "forecast_ordinary_income",
    "FNP"    => "forecast_net_income",
    "FEPS"   => "forecast_eps",
  }.freeze

  # JQUANTS V2 fins/summary → financial_values 固定カラム マッピング（個別）
  JQUANTS_NON_CONSOLIDATED_FIELD_MAP = {
    "NCSales" => :net_sales,
    "NCOP"    => :operating_income,
    "NCOdP"   => :ordinary_income,
    "NCNP"    => :net_income,
    "NCEPS"   => :eps,
    "NCTA"    => :total_assets,
    "NCEq"    => :net_assets,
    "NCBPS"   => :bps,
  }.freeze

  # 整数として扱うカラム
  INTEGER_COLUMNS = %i[
    net_sales operating_income ordinary_income net_income
    total_assets net_assets
    operating_cf investing_cf financing_cf cash_and_equivalents
    shares_outstanding treasury_shares
  ].freeze

  # 小数として扱うカラム
  DECIMAL_COLUMNS = %i[eps diluted_eps equity_ratio bps].freeze

  belongs_to :company
  belongs_to :financial_report, optional: true
  has_one :financial_metric

  enum :scope, { consolidated: 0, non_consolidated: 1 }
  enum :period_type, { annual: 0, q1: 1, q2: 2, q3: 3 }

  define_json_attributes :data_json, schema: {
    dividend_per_share_annual: { type: :decimal },
    total_dividend_paid: { type: :integer },
    payout_ratio: { type: :decimal },
    forecast_net_sales: { type: :integer },
    forecast_operating_income: { type: :integer },
    forecast_ordinary_income: { type: :integer },
    forecast_net_income: { type: :integer },
    forecast_eps: { type: :decimal },
    cost_of_sales: { type: :integer },
    gross_profit: { type: :integer },
    sga_expenses: { type: :integer },
    current_assets: { type: :integer },
    noncurrent_assets: { type: :integer },
    current_liabilities: { type: :integer },
    noncurrent_liabilities: { type: :integer },
    shareholders_equity: { type: :integer },
  }

  # JQUANTS V2 fins/summary のレスポンスデータから属性Hashを生成する
  #
  # @param data [Hash] JQUANTSレスポンスの1件分のHash
  # @param scope_type [Symbol] :consolidated or :non_consolidated
  # @return [Hash] FinancialValue.create / update に渡せる属性Hash
  def self.get_attributes_from_jquants(data, scope_type:)
    field_map = scope_type == :consolidated ?
      JQUANTS_CONSOLIDATED_FIELD_MAP : JQUANTS_NON_CONSOLIDATED_FIELD_MAP

    attrs = {}
    field_map.each do |jquants_key, column|
      raw_value = data[jquants_key]
      attrs[column] = parse_jquants_value(raw_value, column)
    end

    # 連結のみ data_json を設定
    if scope_type == :consolidated
      json_data = {}
      JQUANTS_CONSOLIDATED_DATA_JSON_MAP.each do |jquants_key, json_key|
        raw_value = data[jquants_key]
        json_data[json_key] = parse_jquants_value_raw(raw_value) if raw_value.present?
      end
      attrs[:data_json] = json_data if json_data.any?
    end

    attrs
  end

  # JQUANTS の文字列値をカラムの型に変換する
  #
  # @param raw_value [String, nil] JQUANTS レスポンスの値（全てString型）
  # @param column [Symbol] カラム名
  # @return [Integer, BigDecimal, nil] 変換後の値
  def self.parse_jquants_value(raw_value, column)
    return nil if raw_value.blank? || raw_value == ""

    if INTEGER_COLUMNS.include?(column)
      raw_value.to_i
    elsif DECIMAL_COLUMNS.include?(column)
      BigDecimal(raw_value)
    else
      raw_value
    end
  rescue ArgumentError
    nil
  end

  # JQUANTS の文字列値を数値に変換する（data_json用、型推定）
  #
  # @param raw_value [String] 元の値
  # @return [Integer, Float, String] 変換後の値
  def self.parse_jquants_value_raw(raw_value)
    return nil if raw_value.blank?

    if raw_value.include?(".")
      raw_value.to_f
    else
      raw_value.to_i
    end
  rescue
    raw_value
  end
end
```

### タスク2: ImportJquantsFinancialDataJob の実装

#### ファイル: `app/jobs/import_jquants_financial_data_job.rb`

```ruby
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
```

### タスク3: テスト

#### ファイル: `spec/models/financial_value_spec.rb`

```ruby
RSpec.describe FinancialValue do
  describe ".get_attributes_from_jquants" do
    let(:jquants_data) do
      {
        "Code" => "86970",
        "CurPerType" => "FY",
        "Sales" => "100529000000",
        "OP" => "50000000000",
        "OdP" => "52000000000",
        "NP" => "35000000000",
        "EPS" => "66.76",
        "DEPS" => "66.50",
        "TA" => "500000000000",
        "Eq" => "200000000000",
        "EqRatio" => "40.0",
        "BPS" => "380.50",
        "CFO" => "60000000000",
        "CFI" => "-20000000000",
        "CFF" => "-15000000000",
        "CashEq" => "80000000000",
        "ShOutFY" => "524000000",
        "TrShFY" => "10000000",
        "DivAnn" => "50.0",
        "FSales" => "110000000000",
        "FOP" => "55000000000",
        "NCSales" => "80000000000",
        "NCOP" => "40000000000",
        "NCOdP" => "42000000000",
        "NCNP" => "28000000000",
        "NCEPS" => "53.40",
        "NCTA" => "400000000000",
        "NCEq" => "180000000000",
        "NCBPS" => "343.00",
      }
    end

    context "連結データ" do
      it "固定カラムの属性が正しく変換される" do
        attrs = FinancialValue.get_attributes_from_jquants(jquants_data, scope_type: :consolidated)

        expect(attrs[:net_sales]).to eq(100529000000)
        expect(attrs[:operating_income]).to eq(50000000000)
        expect(attrs[:ordinary_income]).to eq(52000000000)
        expect(attrs[:net_income]).to eq(35000000000)
        expect(attrs[:eps]).to eq(BigDecimal("66.76"))
        expect(attrs[:diluted_eps]).to eq(BigDecimal("66.50"))
        expect(attrs[:total_assets]).to eq(500000000000)
        expect(attrs[:net_assets]).to eq(200000000000)
        expect(attrs[:equity_ratio]).to eq(BigDecimal("40.0"))
        expect(attrs[:bps]).to eq(BigDecimal("380.50"))
        expect(attrs[:operating_cf]).to eq(60000000000)
        expect(attrs[:investing_cf]).to eq(-20000000000)
        expect(attrs[:financing_cf]).to eq(-15000000000)
        expect(attrs[:cash_and_equivalents]).to eq(80000000000)
        expect(attrs[:shares_outstanding]).to eq(524000000)
        expect(attrs[:treasury_shares]).to eq(10000000)
      end

      it "data_jsonの属性が正しく変換される" do
        attrs = FinancialValue.get_attributes_from_jquants(jquants_data, scope_type: :consolidated)

        expect(attrs[:data_json]["dividend_per_share_annual"]).to eq(50.0)
        expect(attrs[:data_json]["forecast_net_sales"]).to eq(110000000000)
        expect(attrs[:data_json]["forecast_operating_income"]).to eq(55000000000)
      end

      it "空文字列はnilに変換される" do
        data = jquants_data.merge("Sales" => "", "OP" => nil)
        attrs = FinancialValue.get_attributes_from_jquants(data, scope_type: :consolidated)

        expect(attrs[:net_sales]).to be_nil
        expect(attrs[:operating_income]).to be_nil
      end
    end

    context "個別データ" do
      it "NC*フィールドから属性が正しく変換される" do
        attrs = FinancialValue.get_attributes_from_jquants(jquants_data, scope_type: :non_consolidated)

        expect(attrs[:net_sales]).to eq(80000000000)
        expect(attrs[:operating_income]).to eq(40000000000)
        expect(attrs[:ordinary_income]).to eq(42000000000)
        expect(attrs[:net_income]).to eq(28000000000)
        expect(attrs[:eps]).to eq(BigDecimal("53.40"))
        expect(attrs[:total_assets]).to eq(400000000000)
        expect(attrs[:net_assets]).to eq(180000000000)
        expect(attrs[:bps]).to eq(BigDecimal("343.00"))
      end

      it "data_jsonは設定されない" do
        attrs = FinancialValue.get_attributes_from_jquants(jquants_data, scope_type: :non_consolidated)

        expect(attrs).not_to have_key(:data_json)
      end
    end
  end

  describe ".parse_jquants_value" do
    it "整数カラムの場合はIntegerに変換する" do
      expect(FinancialValue.parse_jquants_value("100529000000", :net_sales)).to eq(100529000000)
    end

    it "小数カラムの場合はBigDecimalに変換する" do
      expect(FinancialValue.parse_jquants_value("66.76", :eps)).to eq(BigDecimal("66.76"))
    end

    it "空文字列はnilを返す" do
      expect(FinancialValue.parse_jquants_value("", :net_sales)).to be_nil
    end

    it "nilはnilを返す" do
      expect(FinancialValue.parse_jquants_value(nil, :net_sales)).to be_nil
    end

    it "負の値を正しく変換する" do
      expect(FinancialValue.parse_jquants_value("-20000000000", :investing_cf)).to eq(-20000000000)
    end
  end
end
```

---

## 実装順序

1. `app/models/financial_value.rb` に定数とクラスメソッドを追加
2. `app/jobs/import_jquants_financial_data_job.rb` を新規作成
3. `spec/models/financial_value_spec.rb` を新規作成・テスト実行
