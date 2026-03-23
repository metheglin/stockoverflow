# 企業最新スナップショットキャッシュ

## 概要

各企業の最新期の主要指標を非正規化して保持するキャッシュ機構を構築する。
スクリーニングクエリの高速化と、企業一覧表示時のJOINコスト削減を目的とする。

## 背景・動機

- 「6期連続増収増益の企業を一覧」のようなスクリーニングは、financial_metricsテーブルから最新レコードを取得し、
  consecutive_revenue_growth >= 6 でフィルタする必要がある
- 「最新期のROEが15%以上」のような条件は、各企業の最新のfinancial_metricを特定するサブクエリが必要
- 企業数が増えると、毎回のスクリーニングクエリでのJOIN・サブクエリのコストが問題になる
- 最新スナップショットを持つことで、単一テーブルのWHERE句のみで高速にスクリーニングできる

## 設計

### テーブル: company_snapshots

EAVパターンではなく、スクリーニング性能を最優先とした専用テーブル。

```
company_snapshots
  - company_id (FK, unique)
  - fiscal_year_end (date)
  - scope (integer, enum: consolidated/non_consolidated)
  - period_type (integer, enum: annual/q1/q2/q3)
  - financial_value_id (FK)
  - financial_metric_id (FK)

  # 主要スクリーニング指標（実カラム = インデックス可能）
  - revenue (bigint)
  - operating_income (bigint)
  - net_income (bigint)
  - roe (decimal)
  - roa (decimal)
  - operating_margin (decimal)
  - revenue_yoy (decimal)
  - operating_income_yoy (decimal)
  - net_income_yoy (decimal)
  - consecutive_revenue_growth (integer)
  - consecutive_profit_growth (integer)
  - free_cf (bigint)
  - operating_cf_positive (boolean)
  - free_cf_positive (boolean)
  - market_cap (bigint, nullable)
  - data_json (json) # PER, PBR, PSR等の追加指標

  - refreshed_at (datetime)
```

### 更新タイミング

- CalculateFinancialMetricsJob完了後に、対象企業のスナップショットを更新
- 最新のfinancial_metricを特定し、対応するfinancial_valueの値とともにupsert

### インデックス戦略

- `(consecutive_revenue_growth, revenue_yoy)` - 連続増収スクリーニング用
- `(roe)` - ROEスクリーニング用
- `(operating_cf_positive, free_cf_positive)` - CF条件スクリーニング用

## 実装方針

1. マイグレーションでcompany_snapshotsテーブル作成
2. CompanySnapshotモデル作成（belongs_to company, financial_value, financial_metric）
3. スナップショット更新ロジックをCompanySnapshotのクラスメソッドとして実装
4. CalculateFinancialMetricsJobの後処理としてスナップショット更新を呼び出す

## 対象ファイル（新規）

- `db/migrate/xxx_create_company_snapshots.rb`
- `app/models/company_snapshot.rb`

## 対象ファイル（修正）

- `app/jobs/calculate_financial_metrics_job.rb`

## テスト方針

- スナップショット更新メソッドが最新期のデータを正しく反映することのテスト
- 連結・個別が混在する企業で、連結優先のロジックが正しく動作することの確認
