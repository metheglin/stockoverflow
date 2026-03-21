# DEVELOP: 未テストジョブのメソッドテスト追加

## 概要

テスティング規約に基づき、現在テストが存在しない5つのジョブクラスの公開メソッドに対するRSpecテストを追加する。

## 背景・動機

現在、ジョブのテストは `ImportEdinetDocumentsJob` の3メソッド（`normalize_securities_code`, `determine_report_type`, `determine_quarter`）のみ。テスティング規約では「モデル内に切り出されているメソッドがある場合、そのメソッドに対してテストを記述する」と定められており、以下のジョブの多数のメソッドがテスト対象から漏れている。

また、今後のリファクタリング（メトリクス計算プラグインフレームワーク等）を安全に進めるためにも、現行の動作を保証するテストが必要。

## 対象ジョブとテスト対象メソッド

### 1. CalculateFinancialMetricsJob (`spec/jobs/calculate_financial_metrics_job_spec.rb`)

- `build_target_scope(recalculate:, company_id:)` - 対象スコープの構築ロジック
- `find_previous_financial_value(fv)` - 前期FinancialValueの検索ロジック（±1ヶ月の日付範囲マッチング）
- `find_metric(fv)` - 既存メトリクスの検索ロジック
- `load_stock_price(fv)` - 期末日付近の株価検索ロジック（±7日範囲）

### 2. DataIntegrityCheckJob (`spec/jobs/data_integrity_check_job_spec.rb`)

- `check_missing_metrics` - メトリクス欠損検出ロジック
- `check_missing_daily_quotes` - 株価欠損検出ロジック
- `check_consecutive_growth_integrity` - 連続成長整合性検証ロジック
- `check_sync_freshness` - 同期鮮度チェックロジック
- `generate_summary` - データサマリー生成ロジック
- `add_issue(check:, severity:, message:, details:)` - 問題記録ロジック

### 3. SyncCompaniesJob (`spec/jobs/sync_companies_job_spec.rb`)

- `mark_unlisted(synced_codes)` - 未上場マーク処理ロジック

### 4. ImportDailyQuotesJob (`spec/jobs/import_daily_quotes_job_spec.rb`)

- `import_quote(data, company:)` - 個別株価データのインポートロジック
- `get_last_synced_date` - 最終同期日取得ロジック
- `parse_date(value)` - 日付パースロジック

### 5. ImportJquantsFinancialDataJob (`spec/jobs/import_jquants_financial_data_job_spec.rb`)

- `has_non_consolidated_data?(data)` - 個別決算データ有無の判定
- `get_last_synced_date` - 最終同期日取得ロジック
- `parse_date(value)` - 日付パースロジック

## テスト方針

- テスティング規約に従い、ジョブ自体の `perform` 実行テストは記述しない
- なるべくDB読み書きをおこなわないテスト設計を心がける
- DB操作が必要なメソッド（`find_previous_financial_value`, `mark_unlisted` 等）は最小限のDBセットアップで検証
- `FactoryBot` 導入TODO（20260320_0903）が先行実装される場合はそちらを活用するが、未導入でも `build` による手動構築で対応可能

## 優先度

高。既存機能の品質保証と、今後のリファクタリング安全性に直結する。

## 依存関係

- 既存の全ジョブクラスに依存
- `improve_test_data_factories` が先行すると効率的だが、必須ではない
