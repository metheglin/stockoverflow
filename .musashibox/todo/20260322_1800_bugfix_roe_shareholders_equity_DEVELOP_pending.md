# DEVELOP: ROE計算でshareholders_equityを優先使用するバグ修正

## 概要

`FinancialMetric.get_profitability_metrics` において、ROEの算出に `net_assets`（純資産）を使用しているが、正確なROEは `shareholders_equity`（株主資本/自己資本）を分母とすべきである。

## 問題の詳細

### 現在の実装 (`app/models/financial_metric.rb:59`)

```ruby
roe: safe_divide(fv.net_income, fv.net_assets),
```

### 会計上の問題

日本の会計基準において:

- **純資産（net_assets）** = 株主資本 + その他の包括利益累計額 + 新株予約権 + 非支配株主持分
- **株主資本（shareholders_equity）** = 資本金 + 資本剰余金 + 利益剰余金 - 自己株式

ROE = 当期純利益 / 株主資本（自己資本）

`net_assets` を分母にすると、非支配株主持分や新株予約権が含まれるため、特に子会社を多く持つ企業ではROEが過小評価される。

### データの可用性

- `shareholders_equity` は `FinancialValue.data_json` に EDINET XBRL 経由で格納されている（`EdinetXbrlParser` の extended elements）
- JQUANTS経由のデータには `shareholders_equity` が含まれない場合がある
- したがって、`shareholders_equity` が存在する場合はそちらを優先し、存在しない場合は `net_assets` にフォールバックする

## 修正内容

### 1. `FinancialMetric.get_profitability_metrics` の修正

```ruby
def self.get_profitability_metrics(fv)
  equity = fv.shareholders_equity || fv.net_assets

  {
    roe: safe_divide(fv.net_income, equity),
    roa: safe_divide(fv.net_income, fv.total_assets),
    operating_margin: safe_divide(fv.operating_income, fv.net_sales),
    ordinary_margin: safe_divide(fv.ordinary_income, fv.net_sales),
    net_margin: safe_divide(fv.net_income, fv.net_sales),
  }
end
```

### 2. テストの修正

`spec/models/financial_metric_spec.rb` の `get_profitability_metrics` テストを更新:

- `shareholders_equity` が存在する場合、そちらが使われること
- `shareholders_equity` が nil の場合、`net_assets` にフォールバックすること
- 両方 nil の場合、ROE が nil になること

### 3. 既存メトリクスの再計算

修正後、`CalculateFinancialMetricsJob.perform(recalculate: true)` で全メトリクスを再計算する。

## 影響範囲

- `app/models/financial_metric.rb` - `get_profitability_metrics` メソッド
- `spec/models/financial_metric_spec.rb` - 対応テスト
- 既存の `financial_metrics` レコード（再計算が必要）
