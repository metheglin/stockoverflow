# WORKLOG: コード実装分析に基づくギャップ特定

作業日時: 2026-03-22 15:00

## 作業概要

既存の122件のTODOファイルと実装コードを照合し、コードレベルの分析からプロジェクトの主要ユースケース実現に必要な、未カバーの課題5件を特定しTODOとして作成した。

## 分析アプローチ

### 1. コードの精読

以下のファイルを精読し、ロジック上の問題点・欠落を洗い出した:

- `app/models/financial_value.rb` - データマッピングと型変換
- `app/models/financial_metric.rb` - 指標算出ロジック全体
- `app/models/company.rb` - 企業モデルの機能
- `app/models/financial_report.rb` - レポートモデルの関連定義
- `app/jobs/calculate_financial_metrics_job.rb` - メトリクス計算パイプライン
- `app/jobs/import_jquants_financial_data_job.rb` - JQUANTS取り込み処理
- `app/jobs/import_edinet_documents_job.rb` - EDINET取り込み処理
- `db/schema.rb` - テーブル構造・インデックス

### 2. ユースケース逆算

プロジェクトの3大ユースケースから逆算して必要な機能を特定:

- UC1: 「6期連続増収増益の企業一覧」 → **各社最新通期指標への効率的アクセスが不在**
- UC2: 「FCFプラス転換企業一覧」 → **指標の前期比変化（転換）フラグが不在**
- UC3: 「飛躍直前の変化分析」 → 時系列アクセサ（既存TODO）で対応可能

### 3. 既存TODOとの差分確認

122件の既存TODOの概要を確認し、以下が重複しないことを検証:

- 決算期変更ハンドリング: `20260322_0900`（期間欠損検出）とは異なる問題
- ROE修正: 既存TODOに該当なし
- アソシエーション修正: 既存TODOに該当なし
- 最新指標スクリーニング: `20260312_1000`（分析クエリ層）の前提基盤
- トレンド転換検出: `20260319_1401`（転換点検出計画）の具体実装

## 発見した課題と作成したTODO

### TODO 1: 決算期変更時のメトリクス計算ハンドリング
**ファイル**: `20260322_1500_dev_fiscal_year_change_metric_handling_DEVELOP_pending.md`

`CalculateFinancialMetricsJob#find_previous_financial_value` が fiscal_year_end の ±1ヶ月（11〜13ヶ月前）のみを検索しており、決算期変更（例: 3月決算→12月決算）をカバーできない。YoY計算が途切れ、連続増収増益カウントが不正にリセットされる。

### TODO 2: ROE算出ロジックの修正
**ファイル**: `20260322_1501_dev_roe_calculation_correction_DEVELOP_pending.md`

ROEの分母に `net_assets`（純資産）を使用しているが、正しくは `shareholders_equity`（株主資本）。純資産には非支配株主持分が含まれるため、ROEが過小評価される。XBRL由来の `shareholders_equity` が data_json にある場合はそれを優先利用すべき。

### TODO 3: FinancialReport アソシエーション修正
**ファイル**: `20260322_1502_dev_financial_report_association_fix_DEVELOP_pending.md`

`FinancialReport` が `has_one :financial_value` と定義されているが、実際には1レポートに連結・個別の2つの FinancialValue が紐付く。`has_many :financial_values` に修正し、便利メソッド（`consolidated_value`, `non_consolidated_value`）を追加すべき。

### TODO 4: 企業別最新通期指標の取得基盤
**ファイル**: `20260322_1503_dev_company_latest_metric_screening_DEVELOP_pending.md`

スクリーニングユースケースの基盤として、各社の最新通期メトリクスを効率的に取得する `latest_annual` スコープと Company モデルへのアクセサメソッドが必要。現状では複雑なサブクエリを毎回組み立てる必要がある。

### TODO 5: 指標の前期比変化フラグ
**ファイル**: `20260322_1504_dev_metric_transition_detection_DEVELOP_pending.md`

`free_cf_positive` 等の当期値だけでなく、前期からの「転換」を示すフラグ（`free_cf_turned_positive`, `revenue_growth_turned_positive` 等）を `data_json` に記録する。UC2のFCFプラス転換企業一覧の直接的な基盤。

## 考察

### 優先度の所感

5件のTODOのうち、プロジェクトの進行にとって特に影響が大きいのは:

1. **TODO 3（アソシエーション修正）**: バグの性質が強く、他の実装に波及する前に早期修正が望ましい
2. **TODO 2（ROE修正）**: データの正確性に直結する。修正は軽微
3. **TODO 4（スクリーニング基盤）**: 分析クエリ層（既存TODO）の前提となる基盤機能
4. **TODO 5（転換フラグ）**: UC2の実現に直結
5. **TODO 1（決算期変更）**: 発生頻度は低いがデータ品質に影響

### 既存TODOとの依存関係

- TODO 4（スクリーニング基盤）は `20260312_1000_dev_analysis_query_layer` の前提基盤
- TODO 5（転換フラグ）は `20260319_1401_plan_trend_turning_point_detection` の具体実装の一部
- TODO 1（決算期変更）は `20260322_0900_dev_fiscal_period_continuity_verification` と相互補完的
