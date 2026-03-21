# Rake Task Pipeline Operations

## 概要

データ取り込みパイプラインの日常運用に必要なRakeタスク群を整備する。
現在、ジョブクラスは存在するが、ユーザーが簡単にパイプラインを実行する手段がない。
Rakeタスクを通じて、ターミナルからワンコマンドでデータ取り込み・指標計算・整合性チェックを実行できるようにする。

## 背景

- `SyncCompaniesJob`, `ImportJquantsFinancialDataJob`, `ImportEdinetDocumentsJob`, `ImportDailyQuotesJob`, `CalculateFinancialMetricsJob`, `DataIntegrityCheckJob` がすでに実装済み
- これらを個別に、または一括で実行するための CLI インターフェースが不足
- 日常的な運用（毎日の増分取り込み、週次の全量同期など）を容易にしたい

## 実装内容

### 1. 個別タスク

- `rake pipeline:sync_companies` - 企業マスタ同期
- `rake pipeline:import_financials[mode]` - 決算データ取り込み (mode: full/incremental)
- `rake pipeline:import_edinet[date_from,date_to]` - EDINET書類取り込み
- `rake pipeline:import_quotes[mode]` - 株価取り込み (mode: full/incremental)
- `rake pipeline:calculate_metrics` - 財務指標計算
- `rake pipeline:integrity_check` - データ整合性チェック

### 2. 一括タスク

- `rake pipeline:daily` - 日次運用（増分取り込み → 指標計算 → 整合性チェック）
- `rake pipeline:full_sync` - 全量同期（全ジョブをfullモードで順次実行）

### 3. ステータス確認

- `rake pipeline:status` - 最終同期日時・データ件数・直近の整合性チェック結果を表示

## 技術的注意点

- Rakeタスクは `lib/tasks/pipeline.rake` に配置
- 各タスクは対応するJobクラスの `perform_now` を呼び出す
- 実行結果をターミナルに見やすく表示する（成功件数、スキップ件数、エラー件数）
- エラー発生時も処理を中断せず、最後にサマリーを表示
