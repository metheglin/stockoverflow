# DEVELOP: FinancialValue 期間ナビゲーションメソッドの追加

## 概要

FinancialValueモデルに、同一企業・同一スコープの前期・次期・直近N期のFinancialValueを取得するナビゲーションメソッドを追加し、時系列データへのアクセスを共通化する。

## 背景・動機

現在、前期のFinancialValueを取得するロジックは `CalculateFinancialMetricsJob#find_previous_financial_value` に実装されている:

```ruby
def find_previous_financial_value(fv)
  target_date = fv.fiscal_year_end - 1.year
  FinancialValue.where(company_id: fv.company_id, scope: fv.scope, period_type: fv.period_type)
    .where(fiscal_year_end: (target_date - 1.month)..(target_date + 1.month))
    .order(fiscal_year_end: :desc).first
end
```

このロジックは以下の場所でも必要とされる（または将来必要になる）:

- `FinancialMetric::DependencyResolver` (TODO: metric_recalculation_dependency_chain) - 前期・次期の特定
- 企業財務タイムラインビュー (TODO: company_financial_timeline_view) - 連続期間の取得
- 連続成長カウンターの検証 - 時系列順での期間取得
- サプライズ指標計算 - 前期の予想値参照
- 各種CAGR計算 (TODO: cagr_multiyear_growth_metrics) - N期前の値取得

同じロジックを複数箇所で再実装するのは保守性の低下につながるため、モデル層に集約する。

## 実装方針

### FinancialValueへのメソッド追加

```ruby
class FinancialValue < ApplicationRecord
  # 前期（同一企業・同一スコープ・同一期間タイプ）のFinancialValueを返す
  # fiscal_year_endの1年前 ±1ヶ月の範囲で検索
  def previous_annual
    # ...
  end

  # 次期のFinancialValueを返す
  def next_annual
    # ...
  end

  # 直近n期分のFinancialValueを fiscal_year_end 降順で返す（自身を含む）
  def recent_annuals(count)
    # ...
  end

  # 指定した年数前のFinancialValueを返す（CAGR計算用）
  # years_ago: 何年前か
  def get_annual_ago(years_ago)
    # ...
  end
end
```

### 設計上の注意点

- `previous_annual` / `next_annual` はDBクエリを発行するため `load_` prefix ではなく、期間ナビゲーションという「計算された属性」としての位置づけ
- ただし毎回DBクエリが発生するため、メモ化は検討するが `get_annual_ago` のように引数を持つメソッドではメモ化しない（code-style.mdルールに準拠）
- `recent_annuals` は `load_` とすべきか検討するが、ActiveRecord関連の慣習に従い通常のメソッド名とする

### CalculateFinancialMetricsJobのリファクタリング

```ruby
# Before
def find_previous_financial_value(fv)
  target_date = fv.fiscal_year_end - 1.year
  FinancialValue.where(...)...
end

# After
def find_previous_financial_value(fv)
  fv.previous_annual
end
```

## テスト

- `spec/models/financial_value_spec.rb` に追加
- テストケース:
  - 前期データが存在する場合に正しく取得できること
  - 前期データが存在しない場合にnilを返すこと
  - fiscal_year_endが1年±1ヶ月の範囲でマッチすること
  - 同一スコープ・同一period_typeのデータのみが返ること
  - `recent_annuals(n)` が正しい件数・順序で返ること
  - `get_annual_ago(n)` がn年前のデータを返すこと
- DB操作が必要なため、最小限のレコードセットアップで検証

## 依存関係

- 既存の FinancialValue モデルに依存
- 実装後、CalculateFinancialMetricsJob の `find_previous_financial_value` をこのメソッドに置き換える
- metric_recalculation_dependency_chain, cagr_multiyear_growth_metrics 等の基盤となる
