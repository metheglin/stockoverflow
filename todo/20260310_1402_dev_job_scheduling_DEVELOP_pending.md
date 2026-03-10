# DEVELOP: ジョブスケジューリング・初期データロード整備

## 背景

5つのジョブ（SyncCompaniesJob, ImportJquantsFinancialDataJob, ImportEdinetDocumentsJob, ImportDailyQuotesJob, CalculateFinancialMetricsJob）が実装済みだが、定期実行の仕組みや初回データロードの手順が整備されていない。

データを最新の状態に保ち続けるために、ジョブの定期実行設定が必要。また、初回利用時にデータベースをブートストラップするための手順も必要。

## 実装内容

### 1. 初期データロード用 rake タスク

初回のデータベース構築を正しい順序で実行する rake タスクを作成する。

```
rake stockoverflow:bootstrap
```

実行順序:
1. `SyncCompaniesJob.perform_now` - 企業マスター同期
2. `ImportJquantsFinancialDataJob.perform_now(full: true)` - JQUANTS決算データ全件取得
3. `ImportDailyQuotesJob.perform_now(full: true)` - 株価データ全件取得
4. `ImportEdinetDocumentsJob.perform_now` - EDINET決算データ取得（直近30日分）
5. `CalculateFinancialMetricsJob.perform_now` - 指標算出

### 2. 日次定期実行設定

Rails 8 の Solid Queue recurring tasks を利用して定期実行を設定する。

推奨スケジュール:
- SyncCompaniesJob: 週1回（月曜 6:00）
- ImportJquantsFinancialDataJob: 日次（7:00）差分更新
- ImportDailyQuotesJob: 日次（8:00）差分更新
- ImportEdinetDocumentsJob: 日次（9:00）差分更新
- CalculateFinancialMetricsJob: 日次（10:00）指標再算出

### 3. 設定ファイル

- `config/recurring.yml` にスケジュール定義
- Solid Queue が production 環境で利用可能か確認し、必要に応じて設定を調整

## テスト

- rake タスクの実行順序が正しいことの確認（手動テスト）
- テスティング規約に従いジョブの稼働テストは記述しない

## 成果物

- `lib/tasks/stockoverflow.rake` - 初期データロード rake タスク
- `config/recurring.yml` - 定期実行スケジュール定義
- 必要に応じた Solid Queue 関連設定
