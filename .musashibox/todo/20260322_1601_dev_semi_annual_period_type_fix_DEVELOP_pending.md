# Semi-annual period type mapping の修正

## 概要

`ImportEdinetDocumentsJob#determine_quarter` にて、半期報告（semi_annual）が `:q2` にマッピングされている。しかし半期報告（半年間の累計）と第2四半期報告は概念が異なる。

現在の `FinancialValue` および `FinancialMetric` の `period_type` enum は `annual(0), q1(1), q2(2), q3(3)` の4種類のみで、半期を表現できない。

半期報告は主に証券取引法上の中間期（上期6ヶ月分）を指し、Q2累計とは集計範囲が異なるケースがある。これを `:q2` として保存すると、四半期別の時系列分析時にデータの意味が混在する。

## 対象ファイル

- `app/models/financial_value.rb` (period_type enum)
- `app/models/financial_metric.rb` (period_type enum)
- `app/jobs/import_edinet_documents_job.rb` (determine_quarter メソッド)
- `db/migrate/` (新規マイグレーション)
- `spec/jobs/import_edinet_documents_job_spec.rb`

## 実装内容

1. `period_type` enum に `semi_annual: 4` を追加（FinancialValue, FinancialMetric 両方）
2. `ImportEdinetDocumentsJob#determine_quarter` で半期報告を `:semi_annual` にマッピング
3. `CalculateFinancialMetricsJob` で semi_annual の前年比較ロジックを追加
4. 既存テストの更新と新規テストケースの追加

## 注意事項

- 既存データベースに `:q2` として保存された半期データが存在する場合、移行スクリプトが必要
- FinancialReport の `report_type` enum にはすでに `semi_annual: 4` が定義されているため、整合性の確認が必要
