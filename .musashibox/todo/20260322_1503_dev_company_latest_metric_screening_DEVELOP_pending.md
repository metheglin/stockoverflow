# 企業別最新通期指標の取得基盤（スクリーニング基盤）

## 背景・課題

本プロジェクトの主要ユースケースは「条件に合致する企業を一覧する」スクリーニング機能であるが、現状ではそのための基盤が存在しない。

### ユースケース例

1. 「6期連続増収増益の企業を一覧し、増収率が高い順に並べる」
2. 「営業CFプラスかつ投資CFマイナスの企業のうち、FCFがプラスに転換した企業」

これらのクエリを実行するには、**各企業の最新通期データに対してフィルタリングとソートを行う**必要がある。

### 現状の問題

- `FinancialMetric` テーブルには全期間・全四半期のデータが蓄積されており、「各社の最新通期データ」を取得するには `GROUP BY company_id` + サブクエリが必要
- SQLiteでは `ROW_NUMBER()` ウィンドウ関数が使えるものの、毎回複雑なクエリを組み立てるのは効率が悪い
- 企業数が数千社、各社5〜10期分のデータを持つと、適切なインデックスがないとパフォーマンスが劣化する

## 対応方針

### 1. Company モデルへのスクリーニング用メソッド追加

```ruby
class Company < ApplicationRecord
  # 最新通期の FinancialMetric を返す
  # @param scope_type [Symbol] :consolidated or :non_consolidated (default: :consolidated)
  # @return [FinancialMetric, nil]
  def latest_annual_metric(scope_type: :consolidated)
    financial_metrics
      .where(scope: scope_type, period_type: :annual)
      .order(fiscal_year_end: :desc)
      .first
  end

  # 最新通期の FinancialValue を返す
  def latest_annual_value(scope_type: :consolidated)
    financial_values
      .where(scope: scope_type, period_type: :annual)
      .order(fiscal_year_end: :desc)
      .first
  end
end
```

### 2. スクリーニング用スコープの追加

`FinancialMetric` に、各企業の最新通期データのみを返すスコープを追加:

```ruby
class FinancialMetric < ApplicationRecord
  # 各企業の最新通期メトリクスのみを返すスコープ
  scope :latest_annual, -> {
    where(period_type: :annual, scope: :consolidated)
      .where(
        "fiscal_year_end = (
          SELECT MAX(fm2.fiscal_year_end)
          FROM financial_metrics fm2
          WHERE fm2.company_id = financial_metrics.company_id
            AND fm2.period_type = financial_metrics.period_type
            AND fm2.scope = financial_metrics.scope
        )"
      )
  }
end
```

### 3. スクリーニングクエリの実装例

上記スコープを使ったスクリーニング:

```ruby
# ユースケース1: 6期連続増収増益、増収率順
FinancialMetric.latest_annual
  .where("consecutive_revenue_growth >= ?", 6)
  .where("consecutive_profit_growth >= ?", 6)
  .order(revenue_yoy: :desc)
  .includes(:company)

# ユースケース2: CFプラス転換（free_cf_positiveの前期比変化は別TODOで実装）
FinancialMetric.latest_annual
  .where(operating_cf_positive: true, investing_cf_negative: true, free_cf_positive: true)
  .includes(:company)
```

### 4. パフォーマンス考慮

- `financial_metrics` テーブルの `(company_id, scope, period_type, fiscal_year_end)` にはすでにユニークインデックスがあるため、サブクエリは効率的に動作する
- 企業数が増えた場合、キャッシュテーブル（latest_annual_metricsマテリアライズドビュー的なもの）の導入を検討

## テスト観点

- `latest_annual` スコープが各社1件のみを返すことのテスト
- company の `latest_annual_metric` が正しい期のデータを返すテスト
- テストは原則DBアクセスが必要（スコープのテスト）だが、モデルメソッドは最小限のDB利用とする

## 関連TODO

- `20260312_1000_dev_analysis_query_layer`: 分析クエリ層の設計。本TODOはその基盤となるスコープ・メソッドの実装
- `20260322_1002_dev_metric_time_series_accessor`: 時系列アクセサ。本TODOは「最新」のアクセスに特化
