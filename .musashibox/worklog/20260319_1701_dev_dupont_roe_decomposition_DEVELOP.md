# WORKLOG: DuPont ROE分解分析の実装

- 作業日時: 2026-03-25
- 元TODO: `20260319_1701_dev_dupont_roe_decomposition_DEVELOP_done.md`

## 作業概要

ROEを3要素（純利益率 x 総資産回転率 x 財務レバレッジ）に分解するDuPont分析を実装した。

## 作業内容

### 1. FinancialMetric モデルへのメソッド追加

`app/models/financial_metric.rb` に `get_dupont_metrics(fv)` クラスメソッドを追加。

- `dupont_net_margin` = net_income / net_sales
- `dupont_asset_turnover` = net_sales / total_assets
- `dupont_equity_multiplier` = total_assets / net_assets
- `dupont_roe` = net_margin * asset_turnover * equity_multiplier

net_sales, total_assets, net_assets が0またはnilの場合、net_incomeがnilの場合は空Hashを返す。

### 2. data_json スキーマ更新

`define_json_attributes :data_json` のスキーマに4つのDuPontキーを追加:
- `dupont_net_margin`, `dupont_asset_turnover`, `dupont_equity_multiplier`, `dupont_roe`

### 3. CalculateFinancialMetricsJob への統合

`calculate_metrics_for` メソッド内で `get_dupont_metrics` を呼び出し、結果を `json_updates` にmergeするように変更。

### 4. テスト追加

`spec/models/financial_metric_spec.rb` に以下のテストケースを追加:
- 正常ケース: 3要素の分解と検算値（dupont_roe）の一致
- net_salesが0の場合に空Hashを返す
- total_assetsが0の場合に空Hashを返す
- net_assetsが0の場合に空Hashを返す
- net_salesがnilの場合に空Hashを返す
- total_assetsがnilの場合に空Hashを返す
- net_assetsがnilの場合に空Hashを返す
- net_incomeがnilの場合に空Hashを返す
- 赤字企業でもマイナスROEを正しく算出する

全135テスト（既存127 + 新規8）がパス。

## 設計判断

- 既存の `get_profitability_metrics` で算出する `net_margin` と `get_efficiency_metrics` の `asset_turnover` と重複するが、DuPont分析として一貫したprefix (`dupont_`) を付けて独立管理する方針とした。これにより推移分析時にDuPont要素として一括で扱いやすくなる。
- `equity_multiplier` は新規の指標であり、DuPont分析の文脈で最も意味がある。
