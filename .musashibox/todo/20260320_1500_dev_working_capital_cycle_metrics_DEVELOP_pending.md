# DEVELOP: 運転資本サイクル（CCC）メトリクスの実装

## 概要

売上債権回転率・棚卸資産回転率・仕入債務回転率およびキャッシュ・コンバージョン・サイクル（CCC）を算出する。XBRLパーサーの拡張とメトリクス計算の両方を含む。

## 背景

現在のFinancialMetricには効率性指標としてasset_turnover（総資産回転率）が計画されている（`dev_extend_financial_health_metrics`）が、資産回転の内訳を示す運転資本サイクル指標が存在しない。

CCCは企業の資金効率を示す重要な指標であり、以下のプロジェクト目標に直結する:

- **飛躍前兆の検出**: CCCが短縮傾向にある企業は、事業効率が改善しており持続的成長の兆候となりうる
- **キャッシュフロー分析の深化**: 営業CFがプラスであっても、それが運転資本の圧縮によるものか本業の収益によるものかを区別できる
- **業種間比較**: 小売業（低CCC）とメーカー（高CCC）のビジネスモデル差を定量化

## 前提: XBRLパーサーの拡張

### EdinetXbrlParser への追加要素

以下のXBRL要素を `EXTENDED_ELEMENT_MAPPING` に追加する:

```ruby
# 売上債権
trade_receivables: {
  elements: [
    "NotesAndAccountsReceivableTrade",
    "NotesAndAccountsReceivableTradeAndContractAssets",
    "AccountsReceivableTrade",
  ],
  namespace: "jppfs_cor",
},
# 棚卸資産
inventories: {
  elements: [
    "Inventories",
    "MerchandiseAndFinishedGoods",
  ],
  namespace: "jppfs_cor",
},
# 仕入債務
trade_payables: {
  elements: [
    "NotesAndAccountsPayableTrade",
    "AccountsPayableTrade",
  ],
  namespace: "jppfs_cor",
},
```

### FinancialValue data_json スキーマへの追加

```ruby
trade_receivables: { type: :integer },
inventories: { type: :integer },
trade_payables: { type: :integer },
```

## メトリクス算出

### FinancialMetric に `get_working_capital_metrics` を追加

```ruby
# 運転資本サイクル指標を算出する
#
# @param fv [FinancialValue] 当期の財務数値
# @param previous_fv [FinancialValue, nil] 前期の財務数値（平均残高計算用）
# @return [Hash] 運転資本指標のHash（data_json格納用）
#
# 例:
#   result = FinancialMetric.get_working_capital_metrics(current_fv, previous_fv)
#   # => { "receivables_turnover_days" => 45.2, "inventory_turnover_days" => 30.1,
#   #      "payables_turnover_days" => 40.5, "cash_conversion_cycle" => 34.8 }
#
def self.get_working_capital_metrics(fv, previous_fv)
  result = {}
  return result unless fv.net_sales.present? && fv.net_sales > 0

  days = 365.0

  # 売上債権回転日数 = 売上債権 / (売上高 / 365)
  receivables = get_average_balance(fv.trade_receivables, previous_fv&.trade_receivables)
  if receivables.present? && receivables > 0
    result["receivables_turnover_days"] = (receivables.to_d * days / fv.net_sales.to_d).round(1).to_f
  end

  # 棚卸資産回転日数 = 棚卸資産 / (売上原価 / 365)
  # 売上原価がない場合は売上高で代用
  inventories = get_average_balance(fv.inventories, previous_fv&.inventories)
  denominator = fv.cost_of_sales.present? && fv.cost_of_sales > 0 ? fv.cost_of_sales : fv.net_sales
  if inventories.present? && inventories > 0
    result["inventory_turnover_days"] = (inventories.to_d * days / denominator.to_d).round(1).to_f
  end

  # 仕入債務回転日数 = 仕入債務 / (売上原価 / 365)
  payables = get_average_balance(fv.trade_payables, previous_fv&.trade_payables)
  if payables.present? && payables > 0
    result["payables_turnover_days"] = (payables.to_d * days / denominator.to_d).round(1).to_f
  end

  # CCC = 売上債権回転日数 + 棚卸資産回転日数 - 仕入債務回転日数
  if result["receivables_turnover_days"] && result["inventory_turnover_days"] && result["payables_turnover_days"]
    result["cash_conversion_cycle"] = (
      result["receivables_turnover_days"] +
      result["inventory_turnover_days"] -
      result["payables_turnover_days"]
    ).round(1)
  end

  result
end

# 当期末残高と前期末残高の平均を算出（期中平均近似）
# 前期データがなければ当期末残高をそのまま使用
def self.get_average_balance(current, previous)
  return nil if current.nil?
  return current if previous.nil?

  ((current + previous) / 2.0).round(0)
end
```

### data_json スキーマ拡張

```ruby
receivables_turnover_days: { type: :decimal },
inventory_turnover_days: { type: :decimal },
payables_turnover_days: { type: :decimal },
cash_conversion_cycle: { type: :decimal },
```

### CalculateFinancialMetricsJob への組み込み

`calculate_metrics_for(fv)` 内で `get_working_capital_metrics(fv, previous_fv)` を呼び出し、結果を `data_json` にマージする。

## テスト

### FinancialMetric

- `.get_working_capital_metrics`: 全指標が正しく算出されること
- 前期データがない場合に当期末残高のみで算出されること
- 売上債権・棚卸資産・仕入債務のいずれかがnilの場合に該当指標がスキップされCCCも算出不可となること
- 売上原価がない場合に売上高が代用されること
- `.get_average_balance`: 正常系、前期nil、当期nilの各パターン

## 成果物

- `app/lib/edinet_xbrl_parser.rb` - EXTENDED_ELEMENT_MAPPING に3要素追加
- `app/models/financial_value.rb` - data_json スキーマに3属性追加
- `app/models/financial_metric.rb` - `get_working_capital_metrics`, `get_average_balance` メソッド追加 + data_json スキーマ拡張
- `app/jobs/calculate_financial_metrics_job.rb` - 新指標の算出組み込み
- `spec/models/financial_metric_spec.rb` - テスト追加

## 依存関係

- なし（既存のXBRLパーサー・モデル・ジョブの拡張）
- `dev_extend_financial_health_metrics` と並行して実装可能
