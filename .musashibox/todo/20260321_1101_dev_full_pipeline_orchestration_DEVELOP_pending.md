# DEVELOP: データパイプライン全体オーケストレーション

## 概要

企業マスタ同期からデータインポート、メトリクス計算、整合性チェックまでの全パイプラインを正しい順序で一括実行するオーケストレーション機能を実装する。

## 背景・動機

現在、各ジョブ（SyncCompaniesJob, ImportDailyQuotesJob, ImportJquantsFinancialDataJob, ImportEdinetDocumentsJob, CalculateFinancialMetricsJob, DataIntegrityCheckJob）は独立して動作しており、以下の問題がある:

- 正しい実行順序を人間が把握・管理する必要がある
- 前段ジョブの失敗時に後続ジョブの実行可否を判断する仕組みがない
- 「日次の定期実行」「初回フルインポート」といったユースケースに対応するワンコマンドが存在しない
- 既存の「Rakeタスク」TODO（20260320_0902）は個別ジョブのラッパーであり、パイプライン全体のオーケストレーションは含まない
- 既存の「カスケード自動化」TODO（20260320_1900）はインポート→メトリクス計算の連鎖のみで、全体のオーケストレーションではない

## 実装方針

### パイプラインの実行順序

```
1. SyncCompaniesJob          # 企業マスタの最新化
2. ImportDailyQuotesJob      # 日次株価の取り込み
3. ImportJquantsFinancialDataJob  # JQUANTS財務データ
4. ImportEdinetDocumentsJob  # EDINET書類
5. CalculateFinancialMetricsJob   # メトリクス計算
6. DataIntegrityCheckJob     # 整合性チェック
```

### 実行モード

- **daily**: 増分インポート（デフォルト）。日次の定期実行を想定
- **full**: 全件インポート。初回セットアップや完全リフレッシュを想定

### 配置先

`app/jobs/pipeline_orchestration_job.rb` + `lib/tasks/pipeline.rake`

### インターフェース

```ruby
# Job として
PipelineOrchestrationJob.perform_now(mode: :daily)
PipelineOrchestrationJob.perform_now(mode: :full)

# Rake タスクとして
# rake pipeline:daily
# rake pipeline:full
```

### エラーハンドリング

- 各ステップの成否を記録し、失敗時は後続ステップの実行を停止
- ただし、ImportDailyQuotesJob の失敗は他のインポートには影響しないため、独立して処理
- 全ステップ完了後にサマリを出力（成功/失敗/スキップの一覧）

### 実行結果の記録

- ApplicationProperty (kind: :pipeline_execution) にパイプライン実行結果を保存
  - 各ステップの実行結果（success/failure/skipped）
  - 実行開始・終了時刻
  - エラーメッセージ（失敗時）

## 前提・依存

- 既存の全ジョブが正常に動作すること
- Rakeタスク TODO（20260320_0902）と補完的関係。個別タスクはそちら、全体オーケストレーションは本TODO

## テスト

- PipelineOrchestrationJob のモデルメソッド（ステップ順序決定、エラーハンドリング判断等）をテスト
- ジョブ自体の実行テストは記述しない（テスティング規約に準拠）
