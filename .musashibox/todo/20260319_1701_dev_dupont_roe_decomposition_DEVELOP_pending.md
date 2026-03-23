# DuPont ROE分解分析の実装

## 概要

ROEを3要素（純利益率 x 総資産回転率 x 財務レバレッジ）に分解するDuPont分析を実装する。ROEの変動要因を把握でき、「収益性改善によるROE上昇」と「レバレッジ増加によるROE上昇」を区別可能にする。

## 背景

- 現在ROEは `net_income / net_assets` で単一値として算出されている
- ROEが高い企業でも、その要因が収益力なのか借入依存なのかで企業の質が大きく異なる
- 「飛躍し始める直前の変化」を検出するユースケースにおいて、DuPont要素のうちどれが改善し始めたかを把握できることが有用
- 既存TODO `20260319_1400_dev_extend_financial_health_metrics` で `asset_turnover` が計画されているため、そこで追加されるデータを活用する

## 実装内容

### FinancialMetricへのメソッド追加

- `FinancialMetric.get_dupont_metrics(fv)` クラスメソッド
  - 3要素分解:
    - `net_margin` = net_income / net_sales（既存の `get_profitability_metrics` で算出済み）
    - `asset_turnover` = net_sales / total_assets
    - `equity_multiplier` = total_assets / net_assets
  - 検算: `dupont_roe = net_margin * asset_turnover * equity_multiplier`
  - net_sales, total_assets, net_assets のいずれかが0またはnilの場合はnilを返す

### data_jsonへの格納

- `financial_metrics.data_json` に格納する
- キー名: `dupont_net_margin`, `dupont_asset_turnover`, `dupont_equity_multiplier`, `dupont_roe`

### 推移分析への活用

- 各DuPont要素のYoY変化量を算出可能にする（過去のdata_jsonとの差分）
- これにより「総資産回転率が改善し始めた」「レバレッジが低下しつつROEが上昇」などのパターンを検出可能

## テスト

- `get_dupont_metrics` のユニットテスト
  - 正常ケース: 3要素の分解と検算値の一致
  - net_salesが0の場合にnilを返すこと
  - total_assetsが0の場合にnilを返すこと
  - net_assetsが0の場合にnilを返すこと

## 依存関係

- `20260319_1400_dev_extend_financial_health_metrics` の完了後に実装するのが効率的だが、必須ではない（total_assets, net_assets, net_salesは既存カラム）
