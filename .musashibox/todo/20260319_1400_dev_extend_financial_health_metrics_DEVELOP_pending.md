# DEVELOP: 財務健全性・効率性指標の追加

## 背景

現在 `FinancialMetric` で算出される指標は成長性（YoY）、収益性（ROE/ROA/マージン）、CF分析、バリュエーション（PER/PBR/PSR）に限定されている。CLAUDE.mdの「あらゆる指標を分析の対象として」という方針に対し、財務健全性・効率性に関する指標が不足している。

一方で、`FinancialValue` の `data_json` にはEDINETのXBRLパーサーによって以下のデータが既に格納されている:

- `current_assets` (流動資産)
- `current_liabilities` (流動負債)
- `noncurrent_liabilities` (固定負債)
- `shareholders_equity` (株主資本)
- `cost_of_sales` (売上原価)
- `gross_profit` (売上総利益)
- `sga_expenses` (販管費)

これらの既存データを活用して、スクリーニングに有用な財務健全性・効率性指標を新たに算出できる。

## 実装内容

### 1. FinancialMetric に新指標を追加

`data_json` のスキーマに以下の指標を追加する。

```ruby
# app/models/financial_metric.rb
define_json_attributes :data_json, schema: {
  # ... 既存指標 ...

  # 財務健全性
  current_ratio: { type: :decimal },         # 流動比率 = current_assets / current_liabilities
  debt_to_equity: { type: :decimal },        # 負債資本倍率 = (current_liabilities + noncurrent_liabilities) / shareholders_equity
  net_debt_to_equity: { type: :decimal },    # ネット負債資本倍率 = (有利子負債近似 - 現金同等物) / shareholders_equity

  # 効率性
  asset_turnover: { type: :decimal },        # 総資産回転率 = net_sales / total_assets
  gross_margin: { type: :decimal },          # 売上総利益率 = gross_profit / net_sales
  sga_ratio: { type: :decimal },             # 販管費率 = sga_expenses / net_sales
}
```

### 2. FinancialMetric に算出メソッドを追加

```ruby
# 財務健全性指標を算出する
#
# @param fv [FinancialValue] 財務数値
# @return [Hash] 財務健全性指標のHash（data_json格納用）
def self.get_financial_health_metrics(fv)
  result = {}

  current_assets = fv.current_assets
  current_liabilities = fv.current_liabilities
  noncurrent_liabilities = fv.noncurrent_liabilities
  shareholders_equity = fv.shareholders_equity

  # 流動比率
  if current_assets.present? && current_liabilities.present? && current_liabilities != 0
    result["current_ratio"] = (current_assets.to_d / current_liabilities.to_d).round(4).to_f
  end

  # 負債資本倍率
  if current_liabilities.present? && noncurrent_liabilities.present? && shareholders_equity.present? && shareholders_equity != 0
    total_debt = current_liabilities + noncurrent_liabilities
    result["debt_to_equity"] = (total_debt.to_d / shareholders_equity.to_d).round(4).to_f
  end

  # ネット負債資本倍率
  if fv.total_assets.present? && fv.net_assets.present? && fv.cash_and_equivalents.present? && shareholders_equity.present? && shareholders_equity != 0
    debt_approx = fv.total_assets - fv.net_assets
    net_debt = debt_approx - fv.cash_and_equivalents
    result["net_debt_to_equity"] = (net_debt.to_d / shareholders_equity.to_d).round(4).to_f
  end

  result
end

# 効率性指標を算出する
#
# @param fv [FinancialValue] 財務数値
# @return [Hash] 効率性指標のHash（data_json格納用）
def self.get_efficiency_metrics(fv)
  result = {}

  # 総資産回転率
  if fv.net_sales.present? && fv.total_assets.present? && fv.total_assets != 0
    result["asset_turnover"] = (fv.net_sales.to_d / fv.total_assets.to_d).round(4).to_f
  end

  # 売上総利益率
  gross_profit = fv.gross_profit
  if gross_profit.present? && fv.net_sales.present? && fv.net_sales != 0
    result["gross_margin"] = (gross_profit.to_d / fv.net_sales.to_d).round(4).to_f
  end

  # 販管費率
  sga = fv.sga_expenses
  if sga.present? && fv.net_sales.present? && fv.net_sales != 0
    result["sga_ratio"] = (sga.to_d / fv.net_sales.to_d).round(4).to_f
  end

  result
end
```

### 3. CalculateFinancialMetricsJob に組み込み

`CalculateFinancialMetricsJob` のメトリクス算出処理において、上記2つの新メソッドの結果を `data_json` にマージする。

### 4. ScreeningQuery 対応

`Company::ScreeningQuery`（分析クエリレイヤーで実装予定）の `METRIC_FILTER_COLUMNS` に新指標を追加できるよう、data_json指標のフィルタ対応を検討する。

## 前提

- 分析クエリレイヤー（`dev_analysis_query_layer`）の実装完了後に着手するのが望ましい
- ただし FinancialMetric のメソッド追加と CalculateFinancialMetricsJob の修正は独立して実施可能

## テスト

### FinancialMetric

- `.get_financial_health_metrics`: 正常値での算出・各値がnilの場合のスキップ・分母が0の場合のスキップ
- `.get_efficiency_metrics`: 正常値での算出・data_json内の値がnilの場合のスキップ

## 成果物

- `app/models/financial_metric.rb` - 新指標メソッド追加 + data_jsonスキーマ拡張
- `app/jobs/calculate_financial_metrics_job.rb` - 新指標の算出組み込み
- `spec/models/financial_metric_spec.rb` - テスト追加
