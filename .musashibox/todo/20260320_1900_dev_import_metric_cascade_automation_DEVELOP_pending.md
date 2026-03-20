# データインポート後のメトリクス自動再計算パイプライン

## 概要

現在、データインポートジョブ（ImportJquantsFinancialDataJob, ImportEdinetDocumentsJob）と
メトリクス計算ジョブ（CalculateFinancialMetricsJob）は独立して動作しており、
インポート完了後にメトリクスを手動で再計算する必要がある。

データの取り込みからメトリクス更新までを自動化し、常に最新のメトリクスが利用可能な状態を維持する。

## 背景・動機

- ImportJquantsFinancialDataJobがfinancial_valuesを更新しても、financial_metricsは古いまま残る
- ImportEdinetDocumentsJobがdata_jsonを補完しても、拡張データを使うメトリクス（粗利率等）が更新されない
- 手動でCalculateFinancialMetricsJobを実行し忘れると、スクリーニング結果が不正確になる
- 将来的にメトリクスが増えるほど、手動管理は破綻する

## 実装方針

1. **インポートジョブの成果物追跡**
   - 各インポートジョブが更新したcompany_id + fiscal_year_end の組み合わせを記録する
   - ジョブの戻り値またはApplicationPropertyのdata_jsonに影響範囲を記録

2. **カスケード実行の仕組み**
   - インポートジョブの `after_perform` で CalculateFinancialMetricsJob をエンキューする
   - 影響を受けたcompany_idリストを引数として渡し、対象を絞った再計算を実行する
   - CalculateFinancialMetricsJobに `company_ids:` パラメータを追加し、指定企業のみ再計算可能にする

3. **重複実行の防止**
   - 短時間に複数のインポートジョブが完了した場合、メトリクス計算が重複しないよう制御する
   - Solid Queueのuniqueness機能、または一定間隔でのバッチ実行を検討

## 対象ファイル

- `app/jobs/import_jquants_financial_data_job.rb`
- `app/jobs/import_edinet_documents_job.rb`
- `app/jobs/calculate_financial_metrics_job.rb`

## テスト方針

- CalculateFinancialMetricsJobに追加するcompany_ids絞り込みロジックのユニットテスト
- インポートジョブが影響範囲を正しく記録することの確認
