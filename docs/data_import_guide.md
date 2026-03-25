# データインポートジョブ 実行ガイド

本ドキュメントでは、実装済みの全データインポート・算出ジョブについて、実行方法と実行順序をまとめる。

## 前提条件

- Rails credentials に以下のAPIキーが設定されていること
  - `Rails.application.credentials.edinet.api_key`
  - `Rails.application.credentials.jquants.api_key`

## ジョブ一覧と実行順序

以下の順序で実行する。番号が前のジョブが後のジョブの前提データを生成するため、順序を守ること。

| # | ジョブ | データソース | 概要 |
|---|--------|-------------|------|
| 1 | SyncCompaniesJob | JQUANTS | 企業マスター同期 |
| 2 | ImportDailyQuotesJob | JQUANTS | 株価四本値の取り込み |
| 3 | ImportJquantsFinancialDataJob | JQUANTS | 財務情報サマリーの取り込み |
| 4 | ImportEdinetDocumentsJob | EDINET | 決算書類(XBRL)からの取り込み |
| 5 | CalculateFinancialMetricsJob | (内部計算) | 財務指標の算出 |
| 6 | CalculateSectorMetricsJob | (内部計算) | セクター別統計量の算出 |
| 7 | DataIntegrityCheckJob | (内部検証) | データ整合性チェック |

### データ依存関係

```
SyncCompaniesJob
    |
    +---> ImportDailyQuotesJob
    |
    +---> ImportJquantsFinancialDataJob
    |
    +---> ImportEdinetDocumentsJob
              |
              v
    CalculateFinancialMetricsJob  (FinancialValue + DailyQuote が必要)
              |
              v
    CalculateSectorMetricsJob     (FinancialMetric が必要)
              |
              v
    DataIntegrityCheckJob         (全テーブルを検証)
```

- `ImportDailyQuotesJob`, `ImportJquantsFinancialDataJob`, `ImportEdinetDocumentsJob` の3つは互いに依存しないため、並列実行が可能
- `CalculateFinancialMetricsJob` は `FinancialValue`(ジョブ3,4で生成) と `DailyQuote`(ジョブ2で生成) の両方を参照する

---

## 各ジョブの詳細

### 1. SyncCompaniesJob

企業マスターデータをJQUANTS上場銘柄一覧から同期する。全ジョブの起点となる。

```ruby
# 基本実行（credentialsのAPIキーを使用）
SyncCompaniesJob.perform_now

# APIキーを明示的に指定
SyncCompaniesJob.perform_now(api_key: "your_api_key")
```

| パラメータ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `api_key` | String, nil | nil (credentialsから取得) | JQUANTS APIキー |

**処理内容:**
1. JQUANTSから上場銘柄一覧を全件取得
2. `securities_code` をキーに `companies` テーブルへupsert
3. JQUANTS一覧に存在しない既存上場企業を `listed: false` に更新
4. `application_properties` に最終同期時刻を記録

---

### 2. ImportDailyQuotesJob

株価四本値(OHLCV)データを取り込む。

```ruby
# 差分取り込み（前回同期日から当日まで）
ImportDailyQuotesJob.perform_now

# 全件取り込み（2020-01-01から全上場企業分）
ImportDailyQuotesJob.perform_now(full: true)

# 日付範囲を明示
ImportDailyQuotesJob.perform_now(from_date: "2025-01-01", to_date: "2025-03-31")

# 全件取り込み + 日付範囲指定
ImportDailyQuotesJob.perform_now(full: true, from_date: "2024-01-01", to_date: "2024-12-31")
```

| パラメータ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `full` | Boolean | false | trueで全上場企業の過去データを取得 |
| `from_date` | String, nil | nil (前回同期日 or 7日前) | 取得開始日 (YYYY-MM-DD) |
| `to_date` | String, nil | nil (当日) | 取得終了日 (YYYY-MM-DD) |
| `api_key` | String, nil | nil (credentialsから取得) | JQUANTS APIキー |

**処理内容:**
- 差分モード: `from_date`〜`to_date` の日次データを一括取得（土日をスキップ）
- 全件モード: 全上場企業を1社ずつ取得（銘柄間1秒の待機）
- `(company_id, traded_on)` をキーに `daily_quotes` へupsert

**注意:** 全件モードは対象企業数に比例して長時間かかる。初回セットアップ以外では差分モードを推奨。

---

### 3. ImportJquantsFinancialDataJob

JQUANTSの財務情報サマリー（決算短信等）を取り込む。

```ruby
# 差分取り込み（前回同期日以降のデータ）
ImportJquantsFinancialDataJob.perform_now

# 全件取り込み（全上場企業の全期間）
ImportJquantsFinancialDataJob.perform_now(full: true)

# 特定日のデータのみ取り込む
ImportJquantsFinancialDataJob.perform_now(target_date: "2026-03-01")
```

| パラメータ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `full` | Boolean | false | trueで全企業・全期間を取得 |
| `api_key` | String, nil | nil (credentialsから取得) | JQUANTS APIキー |
| `target_date` | String, nil | nil | 特定日のみ取得 (YYYY-MM-DD) |

**処理内容:**
1. JQUANTS財務サマリーAPIからデータ取得
2. `FinancialReport` (source: jquants) を作成/更新
3. `FinancialValue` を連結・個別それぞれ作成/更新
4. API呼び出し間に2秒の待機（レート制限対策）

**出力データ:**
- 売上高、営業利益、経常利益、純利益、EPS、BPS、総資産、純資産、自己資本比率
- キャッシュフロー（営業/投資/財務/現金同等物）
- 業績予想データ（data_json内に格納）

---

### 4. ImportEdinetDocumentsJob

EDINET決算書類（XBRL）を取得・解析してデータを取り込む。

```ruby
# 差分取り込み（前回同期日または30日前から昨日まで）
ImportEdinetDocumentsJob.perform_now

# 日付範囲を明示
ImportEdinetDocumentsJob.perform_now(from_date: "2025-06-01", to_date: "2025-06-30")
```

| パラメータ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `from_date` | String, nil | nil (前回同期日 or 30日前) | 取得開始日 (YYYY-MM-DD) |
| `to_date` | String, nil | nil (昨日) | 取得終了日 (YYYY-MM-DD) |
| `api_key` | String, nil | nil (credentialsから取得) | EDINET APIキー |

**処理内容:**
1. 指定日付範囲の書類一覧を取得し、対象書類種別でフィルタ
   - 120: 有価証券報告書、130: 訂正有価証券報告書
   - 160: 半期報告書、170: 訂正半期報告書
   - 140/150: 四半期報告書
2. XBRL ZIPをダウンロード・パース
3. `FinancialReport` (source: edinet) を作成
4. `FinancialValue` の既存データにXBRL拡張データを補完
   - 拡張データ: 売上原価、売上総利益、販管費、流動資産、固定資産、流動負債、固定負債、株主資本

**注意:**
- 書類間4秒、日付間2秒の待機あり（EDINET推奨）
- JQUANTSデータがある場合は上書きせず、XBRL拡張項目のみ補完する

---

### 5. CalculateFinancialMetricsJob

取り込み済みの財務データから各種分析指標を算出する。

```ruby
# 未算出分のみ計算
CalculateFinancialMetricsJob.perform_now

# 全件再計算
CalculateFinancialMetricsJob.perform_now(recalculate: true)

# 特定企業のみ
CalculateFinancialMetricsJob.perform_now(company_id: 123)

# 特定企業を全件再計算
CalculateFinancialMetricsJob.perform_now(recalculate: true, company_id: 123)
```

| パラメータ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `recalculate` | Boolean | false | trueで全レコードを再計算 |
| `company_id` | Integer, nil | nil | 特定企業のIDに限定 |

**算出される指標:**

| カテゴリ | 指標 |
|---------|------|
| 成長性 | 売上高YoY、営業利益YoY、純利益YoY、EPS YoY |
| 収益性 | ROE、ROA、営業利益率、純利益率、経常利益率 |
| キャッシュフロー | 営業CF正負、投資CF正負、フリーCF正負 |
| 連続成長 | 連続増収期数、連続増益期数 |
| バリュエーション | PER、PBR、PSR、EV/EBITDA (data_json) |
| サプライズ | 実績 vs 予想の乖離 (data_json) |
| 財務健全性 | 流動比率、負債比率 (data_json) |
| 効率性 | 資産回転率、売上総利益率 (data_json) |
| DuPont分解 | ROE三分解 (data_json) |
| 配当 | 配当性向、配当成長率 (data_json) |
| CAGR | 3年/5年CAGR、加速度 (data_json) |
| スコア | 成長/品質/割安/総合スコア (data_json) |

---

### 6. CalculateSectorMetricsJob

企業別指標からセクター別の統計量を算出する。

```ruby
# 全分類（17業種・33業種の両方）
CalculateSectorMetricsJob.perform_now

# 33業種のみ
CalculateSectorMetricsJob.perform_now(classification: "sector_33")

# 17業種のみ
CalculateSectorMetricsJob.perform_now(classification: "sector_17")

# 特定日付のスナップショット
CalculateSectorMetricsJob.perform_now(calculated_on: Date.parse("2026-03-01"))
```

| パラメータ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `classification` | String, nil | nil (両方) | "sector_17" or "sector_33" |
| `calculated_on` | Date | Date.current | スナップショット基準日 |

**算出される統計量（各指標ごと）:** 平均、中央値、Q1、Q3、最小値、最大値、標準偏差、企業数

---

### 7. DataIntegrityCheckJob

全データの整合性・鮮度を検証する。パラメータなし。

```ruby
DataIntegrityCheckJob.perform_now
```

**チェック項目:**
- FinancialValueに対応するFinancialMetricが欠落していないか
- 上場企業の株価データが直近7日以内に存在するか
- 連続増収・増益の値が論理的に正しいか
- 各データソースの同期日時が3日以上経過していないか

**結果:** `application_properties` (kind: data_integrity) に検証結果が保存される。

---

## 初回セットアップ手順

初めてデータを投入する場合、以下の順序でRailsコンソールから実行する。

```ruby
# Step 1: 企業マスター同期
SyncCompaniesJob.perform_now

# Step 2: 株価データ全件取り込み（長時間かかる）
ImportDailyQuotesJob.perform_now(full: true)

# Step 3: JQUANTS財務データ全件取り込み
ImportJquantsFinancialDataJob.perform_now(full: true)

# Step 4: EDINET書類取り込み（日付範囲を指定）
ImportEdinetDocumentsJob.perform_now(from_date: "2024-01-01")

# Step 5: 財務指標算出
CalculateFinancialMetricsJob.perform_now

# Step 6: セクター統計算出
CalculateSectorMetricsJob.perform_now

# Step 7: 整合性チェック
DataIntegrityCheckJob.perform_now
```

## 日次運用手順

日次でデータを最新化する場合。全て差分取り込みとなる。

```ruby
# Step 1: 企業マスター同期
SyncCompaniesJob.perform_now

# Step 2-4: データ取り込み（並列実行可）
ImportDailyQuotesJob.perform_now
ImportJquantsFinancialDataJob.perform_now
ImportEdinetDocumentsJob.perform_now

# Step 5: 指標算出
CalculateFinancialMetricsJob.perform_now

# Step 6: セクター統計算出
CalculateSectorMetricsJob.perform_now

# Step 7: 整合性チェック
DataIntegrityCheckJob.perform_now
```
