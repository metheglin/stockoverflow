# DEVELOP: 原価・販管費構造分析メトリクスの追加

## 概要

EDINET XBRL から取得済みの `data_json` 内の原価構造データ（`cost_of_sales`, `gross_profit`, `sga_expenses`）を活用し、収益構造の分解メトリクスを `CalculateFinancialMetricsJob` で算出する。営業利益率だけでは見えない「利益構造の変化」を捉え、ユースケース3（企業の飛躍直前の変化を調べる）に寄与する。

## 背景・動機

### 現在の収益性メトリクス

```ruby
# FinancialMetric.get_profitability_metrics
operating_margin: safe_divide(fv.operating_income, fv.net_sales)  # 営業利益率
net_margin: safe_divide(fv.net_income, fv.net_sales)              # 純利益率
```

営業利益率は「結果」の指標であり、その内訳（原価率の改善なのか、販管費の削減なのか）がわからない。

### data_json に存在するが未活用のデータ

```ruby
# FinancialValue#define_json_attributes（app/models/financial_value.rb:85-87）
cost_of_sales: { type: :integer },    # 売上原価
gross_profit: { type: :integer },     # 売上総利益
sga_expenses: { type: :integer },     # 販管費
```

これらはEDINET XBRLから取得され、`data_json` に格納されているが、メトリクス算出に使われていない。

### ユースケース3への貢献

「ある企業の業績が飛躍し始める直前にどのような決算・財務上の変化があったか」を調べる際、以下のような分析が可能になる:

- 飛躍の2期前から売上総利益率が改善し始めていた（原価率の低下 = 製品力の向上？）
- 飛躍の1期前から販管費率が低下していた（規模の経済が効き始めた？）
- 営業利益率は変わらないが、原価率と販管費率が逆方向に動いていた（構造転換の兆候）

## 実装内容

### 1. FinancialMetric の data_json スキーマ拡張

```ruby
# app/models/financial_metric.rb
define_json_attributes :data_json, schema: {
  # 既存のバリュエーション指標
  per: { type: :decimal },
  pbr: { type: :decimal },
  # ... (既存)

  # 原価構造メトリクス（新規追加）
  gross_margin: { type: :decimal },       # 売上総利益率 = gross_profit / net_sales
  cost_of_sales_ratio: { type: :decimal }, # 原価率 = cost_of_sales / net_sales
  sga_ratio: { type: :decimal },          # 販管費率 = sga_expenses / net_sales

  # 原価構造YoY（新規追加）
  gross_margin_change: { type: :decimal },       # 売上総利益率の変化幅（pp）
  cost_of_sales_ratio_change: { type: :decimal }, # 原価率の変化幅（pp）
  sga_ratio_change: { type: :decimal },          # 販管費率の変化幅（pp）
}
```

### 2. FinancialMetric にクラスメソッドを追加

```ruby
# app/models/financial_metric.rb

# 原価構造メトリクスを算出する
#
# data_json 内の cost_of_sales, gross_profit, sga_expenses を使用。
# これらのデータは EDINET XBRL 由来であり、全企業・全期間で利用可能とは限らない。
# データが存在しない場合は空Hashを返す。
#
# @param fv [FinancialValue] 当期の財務数値
# @param previous_fv [FinancialValue, nil] 前期の財務数値
# @return [Hash] 原価構造メトリクス（data_json格納用）
#
# 例:
#   result = FinancialMetric.get_cost_structure_metrics(current_fv, previous_fv)
#   # => {
#   #   "gross_margin" => 0.3521,
#   #   "cost_of_sales_ratio" => 0.6479,
#   #   "sga_ratio" => 0.2105,
#   #   "gross_margin_change" => 0.0152,
#   #   "cost_of_sales_ratio_change" => -0.0152,
#   #   "sga_ratio_change" => -0.0083,
#   # }
#
def self.get_cost_structure_metrics(fv, previous_fv)
  return {} unless fv.net_sales.present? && fv.net_sales > 0

  result = {}

  gross_profit = fv.gross_profit
  cost_of_sales = fv.cost_of_sales
  sga_expenses = fv.sga_expenses

  if gross_profit.present?
    current_gross_margin = (gross_profit.to_d / fv.net_sales.to_d).round(4).to_f
    result["gross_margin"] = current_gross_margin
  end

  if cost_of_sales.present?
    current_cos_ratio = (cost_of_sales.to_d / fv.net_sales.to_d).round(4).to_f
    result["cost_of_sales_ratio"] = current_cos_ratio
  end

  if sga_expenses.present?
    current_sga_ratio = (sga_expenses.to_d / fv.net_sales.to_d).round(4).to_f
    result["sga_ratio"] = current_sga_ratio
  end

  # 前期との変化幅を算出
  if previous_fv && previous_fv.net_sales.present? && previous_fv.net_sales > 0
    if result["gross_margin"] && previous_fv.gross_profit.present?
      prev_gm = (previous_fv.gross_profit.to_d / previous_fv.net_sales.to_d).round(4).to_f
      result["gross_margin_change"] = (result["gross_margin"] - prev_gm).round(4)
    end

    if result["cost_of_sales_ratio"] && previous_fv.cost_of_sales.present?
      prev_cos = (previous_fv.cost_of_sales.to_d / previous_fv.net_sales.to_d).round(4).to_f
      result["cost_of_sales_ratio_change"] = (result["cost_of_sales_ratio"] - prev_cos).round(4)
    end

    if result["sga_ratio"] && previous_fv.sga_expenses.present?
      prev_sga = (previous_fv.sga_expenses.to_d / previous_fv.net_sales.to_d).round(4).to_f
      result["sga_ratio_change"] = (result["sga_ratio"] - prev_sga).round(4)
    end
  end

  result
end
```

### 3. CalculateFinancialMetricsJob への統合

```ruby
# app/jobs/calculate_financial_metrics_job.rb の calculate_metrics_for メソッド内

# 既存の指標算出の後に追加
cost_structure = FinancialMetric.get_cost_structure_metrics(fv, previous_fv)

json_updates = {}.merge(valuation).merge(ev_ebitda).merge(surprise).merge(cost_structure)
```

## テスト

### FinancialMetric.get_cost_structure_metrics テスト

**ファイル**: `spec/models/financial_metric_spec.rb`（既存ファイルに追加）

- `gross_profit` が存在する場合に `gross_margin` が正しく算出されること
- `cost_of_sales` が存在する場合に `cost_of_sales_ratio` が正しく算出されること
- `sga_expenses` が存在する場合に `sga_ratio` が正しく算出されること
- 前期データが存在する場合に変化幅（`*_change`）が正しく算出されること
- `gross_profit` が存在しない場合に `gross_margin` が含まれないこと
- `net_sales` が 0 の場合に空Hashが返ること
- 前期データがない場合に `*_change` が含まれないこと

## 注意事項

- データの可用性: EDINET XBRL 由来のデータであり、JQUANTS経由でインポートされた企業には存在しない場合がある。メトリクスが nil であることはエラーではなく、データ不在を意味する
- `gross_margin` + `cost_of_sales_ratio` は理論上 1.0 になるが、丸め誤差により完全一致しない場合がある
- セクター統計（`SectorMetric`）にも追加する場合は、XBRL データが存在する企業のみで統計をとる必要がある

## 関連TODO

- `20260319_1400_dev_extend_financial_health_metrics` - 財務健全性メトリクスの拡張。本TODOは収益構造の分解に特化
- `20260319_1701_dev_dupont_roe_decomposition` - DuPont分解も利益構造分析の一種。本TODOの gross_margin/sga_ratio と相互補完的
- `20260320_1600_dev_company_financial_timeline_view` - タイムラインビューで原価構造の推移を表示する際に本メトリクスを活用
