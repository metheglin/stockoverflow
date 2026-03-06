# EDINET 決算データ取り込みジョブ実装

## 概要

EDINET の書類一覧APIから新着の有価証券報告書・四半期報告書を検出し、XBRLデータを取得・パースして `financial_reports` / `financial_values` テーブルに保存するジョブを実装する。

本ジョブは JQUANTS 決算データ取り込み（`ImportJquantsFinancialDataJob`）の**補完的な位置づけ**である。
JQUANTS から構造化データで取得できる主要財務数値は既に取り込み済みの前提で、EDINET XBRLからは以下を目的として取り込む:
- JQUANTS にない拡張B/S項目（流動資産、固定資産、流動負債、固定負債、株主資本等）の補完
- EDINET独自のメタデータ（docID、提出日時等）の記録
- EDINETコードと証券コードの紐づけ

## 前提知識

### EDINET 書類一覧API

`EdinetApi#load_target_documents(date:)` で対象日の有価証券報告書・四半期報告書等を取得可能。

#### レスポンスフィールド（書類単位）

| フィールド | 説明 | 用途 |
|-----------|------|------|
| `docID` | 書類管理番号 | financial_reports.doc_id |
| `edinetCode` | EDINETコード | companies.edinet_code |
| `secCode` | 証券コード（5桁。末尾0なし4桁の場合あり） | companies.securities_code で検索 |
| `filerName` | 提出者名 | Company.name のフォールバック |
| `docTypeCode` | 書類種別コード | financial_reports.doc_type_code, report_type変換 |
| `periodStart` | 期間開始日 | financial_reports.period_start |
| `periodEnd` | 期間終了日 | financial_reports.period_end, fiscal_year_end |
| `submitDateTime` | 提出日時 | financial_reports.submitted_at |
| `xbrlFlag` | XBRLデータ有無 | フィルタ条件（`load_target_documents` で "1" のみ抽出済み） |
| `withdrawalStatus` | 取下げ状態 | フィルタ条件（`load_target_documents` で "0" のみ抽出済み） |

### XBRL パース

`EdinetXbrlParser` が ZIP → XBRL → 財務数値抽出を担当。

```ruby
parser = EdinetXbrlParser.new(zip_path: zip_file.path)
result = parser.parse
# => {
#   consolidated: { net_sales: 100529000000, ..., extended: { cost_of_sales: ..., ... } },
#   non_consolidated: { ... } or nil
# }
```

#### XBRL抽出値のDB対応

固定カラム対応（`ELEMENT_MAPPING`）:
- `net_sales`, `operating_income`, `ordinary_income`, `net_income`
- `total_assets`, `net_assets`
- `operating_cf`, `investing_cf`, `financing_cf`, `cash_and_equivalents`

拡張要素（`EXTENDED_ELEMENT_MAPPING` → data_json）:
- `cost_of_sales`, `gross_profit`, `sga_expenses`
- `current_assets`, `noncurrent_assets`, `current_liabilities`, `noncurrent_liabilities`, `shareholders_equity`

### docTypeCode → report_type 変換ルール

| docTypeCode | 書類種別 | report_type |
|-------------|---------|-------------|
| 120 | 有価証券報告書 | `annual` |
| 130 | 訂正有価証券報告書 | `annual` |
| 140 | 四半期報告書 | `q1` / `q2` / `q3`（期間から判定） |
| 150 | 訂正四半期報告書 | `q1` / `q2` / `q3`（期間から判定） |
| 160 | 半期報告書 | `semi_annual` |
| 170 | 訂正半期報告書 | `semi_annual` |

四半期の判定ロジック:
- `periodStart` と `periodEnd` の月数差で判定
- 3ヶ月: q1, 6ヶ月: q2, 9ヶ月: q3
- 判定できない場合は `periodEnd` の月と `fiscal_year_end` の月の差で推定

### 実行頻度・運用

- **実行頻度**: 日次
- **差分更新**: `application_properties` (kind: `edinet_sync`) の `last_synced_date` を基準に、未取得日分のデータを取得
- **レート制限への対応**: EDINET APIは書類一覧が1分に1回以下、書類取得が3-5秒間隔を推奨。`sleep` を挟む
- **最終同期日**: `application_properties` (kind: `edinet_sync`) の `last_synced_date` に記録

### EDINETコードの紐づけ

EDINET書類一覧レスポンスには `edinetCode` と `secCode` の両方が含まれる。
`secCode` を正規化（5桁に揃える）して `companies.securities_code` で企業を検索し、
見つかった企業に `edinet_code` を設定する。

```
secCode "72030" → securities_code "72030" → Company 検索 → edinet_code 設定
secCode "7203"  → securities_code "72030" に正規化 → Company 検索
secCode nil     → edinetCode のみで新規企業作成（非上場企業等）
```

### エラーハンドリング

- 書類一覧API失敗時: その日をスキップして次の日へ継続（ログ記録）
- 個別書類のXBRLダウンロード・パース失敗時: ログに記録して次の書類へ継続
- エラーハンドリング規約に従い、バッチ処理全体を1件の失敗で止めない

### データの補完戦略

EDINET XBRLで取得した値の扱い:

1. **financial_values レコードが既に存在する場合**（JQUANTS由来）:
   - 固定カラム（net_sales等）: JQUANTS の値を優先し**上書きしない**
   - data_json の拡張B/S項目: EDINET XBRLの `extended` データで**マージ補完**

2. **financial_values レコードが存在しない場合**:
   - XBRL抽出値で新規作成

---

## 実装タスク

### タスク1: ImportEdinetDocumentsJob の実装

#### ファイル: `app/jobs/import_edinet_documents_job.rb`

```ruby
class ImportEdinetDocumentsJob < ApplicationJob
  SLEEP_BETWEEN_DOCS = 4  # 書類取得間の待機秒数（EDINET推奨3-5秒）
  SLEEP_BETWEEN_DAYS = 2  # 日付間の待機秒数

  # docTypeCode → report_type 変換
  DOC_TYPE_REPORT_MAP = {
    "120" => :annual,      # 有価証券報告書
    "130" => :annual,      # 訂正有価証券報告書
    "160" => :semi_annual, # 半期報告書
    "170" => :semi_annual, # 訂正半期報告書
    # 140, 150 (四半期) は期間から判定
  }.freeze

  # EDINET 決算書類からデータを取り込む
  #
  # @param from_date [String, nil] 取得開始日 (YYYY-MM-DD)。nilの場合はlast_synced_dateから
  # @param to_date [String, nil] 取得終了日 (YYYY-MM-DD)。nilの場合は昨日まで
  # @param api_key [String, nil] APIキー。nilの場合はcredentialsから取得
  #
  def perform(from_date: nil, to_date: nil, api_key: nil)
    @client = api_key ? EdinetApi.new(api_key: api_key) : EdinetApi.default
    @stats = { processed: 0, supplemented: 0, created: 0, skipped: 0, errors: 0 }

    start_date = from_date ? Date.parse(from_date) : get_last_synced_date
    end_date = to_date ? Date.parse(to_date) : Date.yesterday

    (start_date..end_date).each do |date|
      process_date(date)
      sleep(SLEEP_BETWEEN_DAYS) if date < end_date
    end

    record_sync_date(end_date)
    log_result
  end

  private

  # 指定日の書類を処理
  def process_date(date)
    documents = @client.load_target_documents(date: date)
    Rails.logger.info("[ImportEdinetDocumentsJob] #{date}: #{documents.size} documents found")

    documents.each_with_index do |doc, index|
      process_document(doc)
      sleep(SLEEP_BETWEEN_DOCS) if index < documents.size - 1
    end
  rescue => e
    @stats[:errors] += 1
    Rails.logger.error("[ImportEdinetDocumentsJob] Failed to fetch documents for #{date}: #{e.message}")
  end

  # 1件の書類を処理
  def process_document(doc)
    doc_id = doc["docID"]

    # 既にインポート済みの場合はスキップ
    if FinancialReport.exists?(doc_id: doc_id)
      @stats[:skipped] += 1
      return
    end

    # 企業の特定
    company = find_or_create_company(doc)
    unless company
      @stats[:skipped] += 1
      return
    end

    # report_type の判定
    report_type = determine_report_type(doc)
    return unless report_type

    # XBRLのダウンロードとパース
    zip_file = @client.load_xbrl_zip(doc_id: doc_id)
    parser = EdinetXbrlParser.new(zip_path: zip_file.path)
    xbrl_result = parser.parse

    unless xbrl_result
      @stats[:skipped] += 1
      return
    end

    # financial_report の作成
    fiscal_year_end = parse_date(doc["periodEnd"])
    report = create_financial_report(doc, company: company, report_type: report_type)

    # financial_value の作成/補完（連結）
    if xbrl_result[:consolidated]
      upsert_financial_value(
        xbrl_result[:consolidated], company: company, report: report,
        fiscal_year_end: fiscal_year_end, report_type: report_type,
        scope_type: :consolidated
      )
    end

    # financial_value の作成/補完（個別）
    if xbrl_result[:non_consolidated]
      upsert_financial_value(
        xbrl_result[:non_consolidated], company: company, report: report,
        fiscal_year_end: fiscal_year_end, report_type: report_type,
        scope_type: :non_consolidated
      )
    end

    @stats[:processed] += 1
  rescue => e
    @stats[:errors] += 1
    Rails.logger.error(
      "[ImportEdinetDocumentsJob] Failed to process document #{doc["docID"]}: #{e.message}"
    )
  ensure
    zip_file&.close
    zip_file&.unlink
  end

  # 証券コードまたはEDINETコードで企業を検索/作成
  def find_or_create_company(doc)
    sec_code = normalize_securities_code(doc["secCode"])
    edinet_code = doc["edinetCode"]

    # 証券コードで検索
    company = Company.find_by(securities_code: sec_code) if sec_code.present?

    # EDINETコードで検索
    company ||= Company.find_by(edinet_code: edinet_code) if edinet_code.present?

    if company
      # EDINETコード未設定なら設定
      if company.edinet_code.blank? && edinet_code.present?
        company.update!(edinet_code: edinet_code)
      end
      return company
    end

    # 企業が見つからない場合は新規作成（主に非上場企業）
    return nil if doc["filerName"].blank?

    Company.create!(
      edinet_code: edinet_code,
      securities_code: sec_code.presence,
      name: doc["filerName"],
      listed: sec_code.present?,
    )
  end

  # 証券コードを5桁に正規化
  # EDINET APIは4桁で返す場合がある（末尾0なし）
  def normalize_securities_code(code)
    return nil if code.blank?
    code = code.strip
    return nil if code == "0" || code.empty?
    code.length == 4 ? "#{code}0" : code
  end

  # docTypeCodeと期間からreport_typeを判定
  def determine_report_type(doc)
    doc_type_code = doc["docTypeCode"]

    # 有価証券報告書・半期報告書は直接マッピング
    if DOC_TYPE_REPORT_MAP.key?(doc_type_code)
      return DOC_TYPE_REPORT_MAP[doc_type_code]
    end

    # 四半期報告書(140, 150)は期間から判定
    if %w[140 150].include?(doc_type_code)
      return determine_quarter(doc)
    end

    nil
  end

  # 四半期報告書の期間判定
  def determine_quarter(doc)
    period_start = parse_date(doc["periodStart"])
    period_end = parse_date(doc["periodEnd"])
    return nil unless period_start && period_end

    months = ((period_end.year * 12 + period_end.month) -
              (period_start.year * 12 + period_start.month))

    case months
    when 0..4  then :q1  # 約3ヶ月
    when 5..7  then :q2  # 約6ヶ月
    when 8..10 then :q3  # 約9ヶ月
    else :annual          # 12ヶ月以上は通期扱い
    end
  end

  # financial_report を作成
  def create_financial_report(doc, company:, report_type:)
    FinancialReport.create!(
      company: company,
      doc_id: doc["docID"],
      doc_type_code: doc["docTypeCode"],
      report_type: report_type,
      source: :edinet,
      period_start: parse_date(doc["periodStart"]),
      period_end: parse_date(doc["periodEnd"]),
      fiscal_year_end: parse_date(doc["periodEnd"]),
      submitted_at: doc["submitDateTime"].present? ? Time.parse(doc["submitDateTime"]) : nil,
    )
  end

  # financial_value の作成/補完
  #
  # 既存レコード（JQUANTS由来）がある場合: data_jsonの拡張項目のみマージ
  # 既存レコードがない場合: XBRL抽出値で新規作成
  def upsert_financial_value(xbrl_values, company:, report:, fiscal_year_end:, report_type:, scope_type:)
    return if fiscal_year_end.nil?

    period_type = report_type == :semi_annual ? :q2 : report_type
    scope_int = scope_type == :consolidated ? 0 : 1
    period_type_int = FinancialValue.period_types[period_type]

    fv = FinancialValue.find_or_initialize_by(
      company: company,
      fiscal_year_end: fiscal_year_end,
      scope: scope_int,
      period_type: period_type_int,
    )

    if fv.persisted?
      # 既存レコードがある場合: 拡張データのみマージ補完
      supplement_with_xbrl(fv, xbrl_values)
      @stats[:supplemented] += 1
    else
      # 新規レコード: XBRL抽出値で作成
      create_from_xbrl(fv, xbrl_values, report: report)
      @stats[:created] += 1
    end
  end

  # 既存 financial_value にXBRLの拡張データをマージ補完
  def supplement_with_xbrl(fv, xbrl_values)
    extended = xbrl_values[:extended] || {}
    return if extended.empty?

    current_json = fv.data_json || {}
    merged = current_json.merge(extended.transform_keys(&:to_s))

    if merged != current_json
      fv.update!(data_json: merged)
    end
  end

  # XBRL抽出値から financial_value を新規作成
  def create_from_xbrl(fv, xbrl_values, report:)
    # 固定カラムの設定
    %i[net_sales operating_income ordinary_income net_income
       total_assets net_assets
       operating_cf investing_cf financing_cf cash_and_equivalents].each do |col|
      fv.send(:"#{col}=", xbrl_values[col]) if xbrl_values.key?(col)
    end

    # 拡張データの設定
    extended = xbrl_values[:extended] || {}
    fv.data_json = extended.transform_keys(&:to_s) if extended.any?

    fv.financial_report = report
    fv.save!
  end

  # 最終同期日を取得（未設定時は30日前）
  def get_last_synced_date
    prop = ApplicationProperty.find_by(kind: :edinet_sync)
    if prop&.last_synced_date.present?
      Date.parse(prop.last_synced_date)
    else
      30.days.ago.to_date
    end
  end

  # 最終同期日を記録
  def record_sync_date(date)
    prop = ApplicationProperty.find_or_create_by!(kind: :edinet_sync)
    prop.last_synced_date = date.iso8601
    prop.save!
  end

  def log_result
    Rails.logger.info(
      "[ImportEdinetDocumentsJob] Completed: " \
      "#{@stats[:processed]} processed, #{@stats[:supplemented]} supplemented, " \
      "#{@stats[:created]} created, #{@stats[:skipped]} skipped, #{@stats[:errors]} errors"
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

### タスク2: テスト

#### ファイル: `spec/jobs/import_edinet_documents_job_spec.rb`

テスティング規約に従い、ジョブの稼働テストは記述しない。

以下のメソッドはジョブ内でpublic定義し、単体テスト可能にすることを検討:

- `normalize_securities_code`: 証券コードの正規化
- `determine_report_type`: docTypeCodeからreport_typeの判定
- `determine_quarter`: 四半期の期間判定

```ruby
RSpec.describe ImportEdinetDocumentsJob do
  let(:job) { ImportEdinetDocumentsJob.new }

  describe "#normalize_securities_code" do
    it "4桁コードを5桁に正規化する" do
      expect(job.normalize_securities_code("7203")).to eq("72030")
    end

    it "5桁コードはそのまま返す" do
      expect(job.normalize_securities_code("72030")).to eq("72030")
    end

    it "空文字列はnilを返す" do
      expect(job.normalize_securities_code("")).to be_nil
    end

    it "nilはnilを返す" do
      expect(job.normalize_securities_code(nil)).to be_nil
    end

    it "'0'はnilを返す" do
      expect(job.normalize_securities_code("0")).to be_nil
    end
  end

  describe "#determine_report_type" do
    it "docTypeCode 120 は annual を返す" do
      expect(job.determine_report_type({ "docTypeCode" => "120" })).to eq(:annual)
    end

    it "docTypeCode 160 は semi_annual を返す" do
      expect(job.determine_report_type({ "docTypeCode" => "160" })).to eq(:semi_annual)
    end

    it "docTypeCode 140 は期間から四半期を判定する" do
      doc = {
        "docTypeCode" => "140",
        "periodStart" => "2024-04-01",
        "periodEnd" => "2024-06-30",
      }
      expect(job.determine_report_type(doc)).to eq(:q1)
    end

    it "6ヶ月の四半期報告書は q2 を返す" do
      doc = {
        "docTypeCode" => "140",
        "periodStart" => "2024-04-01",
        "periodEnd" => "2024-09-30",
      }
      expect(job.determine_report_type(doc)).to eq(:q2)
    end

    it "9ヶ月の四半期報告書は q3 を返す" do
      doc = {
        "docTypeCode" => "140",
        "periodStart" => "2024-04-01",
        "periodEnd" => "2024-12-31",
      }
      expect(job.determine_report_type(doc)).to eq(:q3)
    end
  end
end
```

---

## 設計判断

### データ補完の方針

JQUANTS由来の `financial_values` が既に存在する場合、固定カラムは**一切上書きしない**。
理由: JQUANTS は構造化データを提供し、XBRL パースの不正確さ（勘定科目の揺れ等）よりも信頼性が高い。
EDINET XBRLの価値は、JQUANTS に含まれない拡張B/S項目の補完にある。

### Tempfileのクリーンアップ

XBRLのZIPファイルは `Tempfile` で取得されるため、処理後に `close` + `unlink` で確実に削除する。
`ensure` ブロックで実装し、例外発生時もクリーンアップされるようにする。

### レート制限対応

EDINET APIの推奨間隔（書類取得3-5秒）を遵守するため `SLEEP_BETWEEN_DOCS = 4` を設定。
書類一覧取得間にも `SLEEP_BETWEEN_DAYS = 2` を設定。

---

## 実装順序

1. `app/jobs/import_edinet_documents_job.rb` を新規作成
2. `spec/jobs/import_edinet_documents_job_spec.rb` を新規作成・テスト実行
