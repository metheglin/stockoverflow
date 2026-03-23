# DEVELOP: 新規検出企業の自動データバックフィル

## 概要

SyncCompaniesJobで新たに検出された企業（新規上場、データソース追加等）に対し、過去の財務データ・株価データを自動的にバックフィルする仕組みを実装する。現状では新規企業が追加されても過去データが欠損したままとなり、YoY計算やCAGR、トレンド分析が不完全になる。

## 背景

- SyncCompaniesJobは新規企業を `companies` テーブルに追加するが、財務データのバックフィルはトリガーされない
- `plan_historical_data_backfill` は全上場企業の一括バックフィルを計画しているが、「新規に検出された企業のみ」を対象とした自動的なバックフィルの仕組みは含まれていない
- 新規上場企業はIPO直後から注目度が高く、過去データの迅速なバックフィルが特に重要
- ImportJquantsFinancialDataJob は `full: true` モードで全銘柄取得可能だが、毎回全銘柄をフル取得するのはAPIレート制限とパフォーマンスの観点から非効率

## 実装内容

### 1. 新規企業検出の仕組み

SyncCompaniesJob内で、新規作成された企業のIDリストを記録する。

```ruby
# SyncCompaniesJob#perform 内
# upsert後に新規作成された企業を識別
new_company_ids = # upsert結果から新規作成分を抽出

# 新規企業があればバックフィルジョブをキューに追加
if new_company_ids.any?
  BackfillCompanyDataJob.perform_later(company_ids: new_company_ids)
end
```

### 2. BackfillCompanyDataJob

**配置先**: `app/jobs/backfill_company_data_job.rb`

```ruby
class BackfillCompanyDataJob < ApplicationJob
  # 指定された企業のデータをバックフィルする
  #
  # @param company_ids [Array<Integer>] バックフィル対象の企業ID
  # @param backfill_years [Integer] 何年分遡るか（デフォルト: 5）
  #
  def perform(company_ids:, backfill_years: 5)
    @stats = { companies: 0, financial_values: 0, daily_quotes: 0, errors: 0 }
    companies = Company.where(id: company_ids)

    companies.find_each do |company|
      backfill_company(company, backfill_years)
    end

    log_result
  end

  private

  def backfill_company(company, backfill_years)
    backfill_financial_data(company)
    backfill_daily_quotes(company, backfill_years)
    calculate_metrics(company)
    @stats[:companies] += 1
  rescue => e
    @stats[:errors] += 1
    Rails.logger.error(
      "[BackfillCompanyDataJob] Failed for #{company.securities_code}: #{e.message}"
    )
  end

  # JQUANTSから過去の財務データを取得
  def backfill_financial_data(company)
    # securities_codeを使ってJQUANTS APIから全期間の財務データを取得
    # 既存のImportJquantsFinancialDataJobと同様のロジックで
    # FinancialReport + FinancialValue を作成
  end

  # JQUANTSから過去の株価データを取得
  def backfill_daily_quotes(company, backfill_years)
    from_date = Date.current - backfill_years.years
    # securities_codeを使ってJQUANTS APIから株価を取得
    # 既存のImportDailyQuotesJobと同様のロジックでDailyQuoteを作成
  end

  # バックフィルしたデータのメトリクスを計算
  def calculate_metrics(company)
    CalculateFinancialMetricsJob.perform_now(company_id: company.id)
  end
end
```

### 3. 既存ジョブとのロジック共有

- ImportJquantsFinancialDataJobとImportDailyQuotesJobの内部ロジックをモデルのクラスメソッドに切り出すか、共通モジュールとして抽出することを検討
- ただし過度なリファクタリングは避け、最小限の共有（API呼び出し→upsertのコアロジック）に留める

### 4. APIレート制限への配慮

- 1企業ずつ順番に処理し、API呼び出し間に適切な間隔を設ける
- JquantsApiの既存リトライ・バックオフ機能を活用
- 大量の新規企業が一度に検出された場合（初回実行時等）はバッチサイズを制限

### 5. データの優先度

- 財務データ: 直近5年分を優先取得（CAGR 5年計算に必要な最小限）
- 株価データ: 直近5年分を取得（バリュエーション指標の算出に使用）
- EDINETデータ: バックフィル対象外（日付指定APIのため銘柄単位の取得が困難。通常のバッチで補完）

## テスト

- BackfillCompanyDataJob のモデルメソッド部分のテスト
  - 企業情報からJQUANTS APIのパラメータが正しく構築されること
  - 既存データがある場合に重複作成されないこと（upsertの挙動）
- SyncCompaniesJobとの連携
  - テスティング規約に従いジョブ実行テストは書かないが、新規企業検出ロジックが正しく動作することをモデルメソッドレベルで検証

## 依存関係

- SyncCompaniesJob（新規企業検出トリガー）
- ImportJquantsFinancialDataJob / ImportDailyQuotesJob（ロジック参照）
- CalculateFinancialMetricsJob（メトリクス再計算）

## 関連TODO

- `plan_historical_data_backfill` - 一括バックフィル（本TODOは新規企業の自動バックフィル）
- `dev_import_metric_cascade_automation` - インポート→メトリクス計算の連鎖自動化
- `dev_full_pipeline_orchestration` - パイプライン全体のオーケストレーション
