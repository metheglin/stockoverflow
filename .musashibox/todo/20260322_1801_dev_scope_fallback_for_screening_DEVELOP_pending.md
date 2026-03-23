# DEVELOP: スクリーニングにおける連結/個別スコープフォールバック

## 概要

現在のスクリーニング設計（`Company::ConsecutiveGrowthQuery` 等）は `consolidated`（連結）スコープをデフォルトとしている。しかし、子会社を持たない企業は個別（`non_consolidated`）データのみを報告しており、連結スコープでは一切のスクリーニング対象に含まれない。この問題を解決するため、企業ごとに「利用可能な最適スコープ」を判定し、フォールバックする仕組みを導入する。

## 問題の詳細

### 現状

- `FinancialValue` / `FinancialMetric` は `scope` カラムで `consolidated(0)` / `non_consolidated(1)` を区別
- スクリーニングクエリは `.where(scope: :consolidated)` で固定されている
- 子会社を持たない上場企業は連結決算を公表しない → `scope = consolidated` のレコードが存在しない
- 結果として、これらの企業はスクリーニング結果に一切表示されない

### 影響

- 東証上場企業の約15-20%は非連結企業（推定）
- 特に小型株・新興企業に非連結企業が多く、成長スクリーニングの対象として重要
- 「6期連続増収増益」のような条件に該当する優良企業を見逃す可能性

## 実装方針

### 1. Company に `preferred_scope` メソッドを追加

```ruby
# app/models/company.rb

# 分析に使用すべきスコープを判定する
#
# 連結データが存在する場合は :consolidated、
# 存在しない場合は :non_consolidated を返す。
# period_type を指定することで、通期/四半期ごとに判定可能。
#
# @param period_type [Symbol] :annual, :q1, :q2, :q3（デフォルト: :annual）
# @return [Symbol] :consolidated or :non_consolidated
#
# 例:
#   company.preferred_scope              # => :consolidated
#   company.preferred_scope(:annual)     # => :non_consolidated （個別のみの企業）
#
def preferred_scope(period_type = :annual)
  has_consolidated = financial_values
    .where(scope: :consolidated, period_type: period_type)
    .exists?
  has_consolidated ? :consolidated : :non_consolidated
end
```

### 2. FinancialMetric に `preferred_scope_latest` スコープを追加

```ruby
# app/models/financial_metric.rb

# 企業ごとに利用可能な最適スコープの最新期メトリクスを取得する
#
# 連結データがある企業は連結を、ない企業は個別を使用する
# SQLサブクエリで実現し、N+1を回避する
scope :preferred_scope_latest, -> {
  where(
    "financial_metrics.scope = CASE " \
    "WHEN EXISTS (" \
    "  SELECT 1 FROM financial_metrics fm_c " \
    "  WHERE fm_c.company_id = financial_metrics.company_id " \
    "  AND fm_c.scope = 0 " \
    "  AND fm_c.period_type = financial_metrics.period_type" \
    ") THEN 0 ELSE 1 END"
  )
}
```

### 3. スクリーニングQueryObjectの修正

`Company::ConsecutiveGrowthQuery` / `Company::CashFlowTurnaroundQuery` / `Company::ScreeningQuery` に `scope_type: :auto` オプションを追加。`:auto` 指定時は `preferred_scope_latest` スコープを使用する。

```ruby
# scope_type: :auto の場合
if @scope_type == :auto
  scope = scope.preferred_scope_latest
else
  scope = scope.where(scope: @scope_type)
end
```

### 4. Company に `consolidated_only?` / `non_consolidated_only?` メソッドを追加

```ruby
# スクリーニング結果の表示時に、どのスコープのデータかをユーザーに明示するために使用
def consolidated_only?
  financial_values.where(scope: :non_consolidated).none?
end

def non_consolidated_only?
  financial_values.where(scope: :consolidated).none?
end
```

## テスト

### Company#preferred_scope テスト
- 連結・個別両方のデータがある場合に `:consolidated` を返すこと
- 個別データのみの場合に `:non_consolidated` を返すこと
- データが一切ない場合に `:non_consolidated` を返すこと（安全なデフォルト）

### FinancialMetric.preferred_scope_latest テスト
- テスティング規約によりscopeテストは記述しないが、QueryObjectのテストで間接的にカバー

## 注意事項

- パフォーマンス: `preferred_scope_latest` のサブクエリはインデックス `idx_fin_metrics_unique` のプレフィックス（company_id, scope）を活用できるため効率的
- 混在表示: スクリーニング結果に連結/個別が混在する場合、結果のHashに `scope: :consolidated / :non_consolidated` を含め、ユーザーが判別できるようにする
- 企業比較: 連結と個別の数値は直接比較できないため、セクター統計算出時にも同様のフォールバックが必要

## 関連TODO

- `20260312_1000_dev_analysis_query_layer_DEVELOP_pending` - スクリーニングQueryObjectの基盤実装。本TODOの修正はその実装と合わせて反映する
- `20260316_1000_dev_sector_analysis_foundation_DEVELOP_pending` - セクター統計算出時にも同様の考慮が必要
