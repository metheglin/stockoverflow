# WORKLOG: コードレベルギャップ分析 THINK

## 作業日時

2026-03-22 17:00 JST

## 元TODO

なし（THINK タスク）

## 作業概要

プロジェクトの現状を包括的に調査し、既存の125件以上のpending TODOと重複しない5つの新たなTODOを作成した。

## 分析のアプローチ

### 1. 全体構造の把握

- プロジェクト全体のディレクトリ構造、6つのDBテーブル、7つのモデル、3つのAPIクライアント、6つのジョブ、10のスペックファイルを確認
- 既存TODO 125件以上の内容をカテゴリ別に整理し、カバー範囲を把握

### 2. 重複回避のための精査

以下の既存TODOを特に精読し、類似テーマの重複を避けた:

- `dev_company_lifecycle_tracking` / `dev_company_event_log` → 企業ライフサイクル系は既にカバー
- `improve_import_fault_tolerance` → インポート耐障害性は既にカバー
- `dev_metric_recalculation_dependency_chain` → メトリクス再計算の依存関係は既にカバー
- `dev_cross_source_data_validation` → クロスソース検証は既にカバー
- `plan_data_model_extensibility_review` → data_json拡張性は既にカバー
- `dev_company_latest_metric_screening` → 最新メトリクススクリーニングは既にカバー
- `dev_metric_time_series_accessor` → 時系列アクセサは既にカバー

キーワード検索で「concurrent」「lock」「排他」「json schema evolution」「名寄せ」等を既存TODOから横断検索し、カバーされていないテーマを特定した。

### 3. ソースコード精読によるバグ発見

`CalculateFinancialMetricsJob` と `FinancialMetric` のソースコードを精読し、以下の重要なバグを発見:

**find_each の処理順序バグ**: `find_each` はデフォルトで id 順に処理するが、`consecutive_revenue_growth` の計算は前期のメトリクスに依存する。過去データの後追いインポート（id が新しいが fiscal_year_end が古い）が発生した場合、処理順序が逆転し、連続成長カウンターが不正確になる。これは recalculate: true での全再計算時に特に問題となる。

### 4. 運用・セットアップ視点での欠落

- ApplicationProperty の初期レコードが seeds.rb で作成されていないことを確認
- ジョブの排他ロック機構が存在しないことを確認
- SQL文字列補間のセキュリティリスクを確認

## 考えたこと

- 125件以上のTODOが積み上がっている状況で、さらにTODOを追加することの是非を検討した
- 結論: 機能追加よりも**データ正確性のバグ修正**、**運用安全性の向上**、**実行優先順位の整理**に焦点を当てるべき
- 特に、3つのコアユースケースがいまだに動作しない状態であるため、実行可能にするためのロードマップ策定（PLAN TODO）が最も価値がある

## 作成したTODO

1. `20260322_1700_bugfix_metric_calculation_processing_order_DEVELOP_pending.md`
   - CalculateFinancialMetricsJob の find_each 処理順序バグ修正（優先度: 高）
   - データ正確性に直結する実装バグ

2. `20260322_1701_dev_job_execution_lock_mechanism_DEVELOP_pending.md`
   - ジョブの排他ロック機構実装（優先度: 中）
   - 同一ジョブの並行実行によるデータ競合を防止

3. `20260322_1702_dev_application_property_seeding_DEVELOP_pending.md`
   - ApplicationProperty 初期レコード作成（優先度: 中）
   - 新規環境セットアップの安定性向上

4. `20260322_1703_plan_minimum_viable_screening_path_PLAN_pending.md`
   - コアユースケース実現のための最短経路ロードマップ策定（優先度: 高）
   - 125以上のTODOから真に必要なものを特定

5. `20260322_1704_improve_calculate_metrics_sql_safety_DEVELOP_pending.md`
   - load_stock_price のSQL文字列補間修正（優先度: 低）
   - セキュリティベストプラクティスに準拠
