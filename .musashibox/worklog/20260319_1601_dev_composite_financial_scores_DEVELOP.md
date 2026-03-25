# 複合財務スコアリングシステム実装 作業ログ

作業日時: 2026-03-25

## 作業概要

`FinancialMetric` モデルに複合財務スコアリングシステムを実装した。個別の財務指標（成長率、収益性、CF健全性、バリュエーション等）を統合し、percentile rankベースの0〜100スコアとして企業をランキング可能にした。

## 実装内容

### 1. data_json スキーマ拡張

`financial_metrics.data_json` に4つのスコア属性を追加:
- `growth_score` (Float): 成長性スコア
- `quality_score` (Float): 質スコア
- `value_score` (Float): 割安度スコア
- `composite_score` (Float): 総合スコア

### 2. スコア計算用定数

各スコアの重み配分を定数として定義:

- `GROWTH_SCORE_WEIGHTS`: revenue_yoy(25%), operating_income_yoy(25%), eps_yoy(20%), consecutive_revenue_growth(15%), consecutive_profit_growth(15%)
- `QUALITY_SCORE_WEIGHTS`: roe(25%), operating_margin(25%), cf_health(20%), free_cf_positive(15%), roa(15%)
- `VALUE_SCORE_WEIGHTS`: per_inverse(30%), pbr_inverse(30%), ev_ebitda_inverse(20%), dividend_yield(20%)
- `COMPOSITE_SCORE_WEIGHTS`: growth_score(35%), quality_score(40%), value_score(25%)

### 3. 実装メソッド

- `percentile_ranks(values)`: 値の配列からpercentile rank (0〜100) を算出。同値のtie処理（平均順位ベース）、nil保持に対応。
- `get_growth_scores(metrics)`: 成長性スコアをバッチ算出
- `get_quality_scores(metrics)`: 質スコアをバッチ算出
- `get_value_scores(metrics)`: 割安度スコアをバッチ算出（PER/PBR/EV_EBITDAは逆数化してpercentile化）
- `get_composite_scores(metrics)`: 総合スコアをバッチ算出
- `compute_weighted_scores(metrics, weights, &block)`: 上記4つの共通基盤となる汎用重み付きスコア算出メソッド

### 4. CalculateFinancialMetricsJob 統合

- `perform` メソッドに `calculate_scores` 呼び出しを追加（個別metrics算出完了後）
- `calculate_scores` メソッドを新設: fiscal_year_end + period_type + scope の組み合わせごとにバッチでスコア算出
- Growth/Quality/Value スコアを先に格納し、その後 Composite スコアを算出する2段階処理

### 5. 設計上の考慮事項

- NULL値の指標は当該項目のウェイトを除外し、有効な指標のウェイトのみで再配分
- percentile計算は同一期間・同一scope・同一period_typeの全企業を母集団とする
- Value Score ではPER/PBR/EV_EBITDAが0以下の場合はnil扱い（赤字企業等）
- 同値はすべて同じpercentile（平均順位ベース）

### 6. テスト

以下のテストを追加（合計20テスト）:

- `.percentile_ranks`: 8テスト（均等分布、逆順、同値tie、nil混在、全nil、単一要素、空配列、全同値）
- `.get_growth_scores`: 3テスト（複数メトリクス、nil指標のウェイト再配分、空配列）
- `.get_quality_scores`: 2テスト（複数メトリクス、CF nil時のウェイト再配分）
- `.get_value_scores`: 2テスト（割安度算出、PER負値のnil扱い）
- `.get_composite_scores`: 3テスト（正常算出、部分nil、全nil）
- `.compute_weighted_scores`: 2テスト（全同値→50.0、全nil→nil）

全226テスト pass（新規20 + 既存64 + 他スペック142）

## 変更ファイル

- `app/models/financial_metric.rb`: スキーマ拡張、定数定義、6つのクラスメソッド追加
- `app/jobs/calculate_financial_metrics_job.rb`: `calculate_scores` メソッド追加、`perform` への統合
- `spec/models/financial_metric_spec.rb`: 20テスト追加
