# 営業レバレッジ分析の実装

## 概要

営業レバレッジ（売上高変動に対する営業利益変動の感応度）を算出し、企業の固定費構造とリスク特性を把握可能にする。売上増加時に利益が加速度的に増えるか、売上減少時にどの程度利益が削られるかを定量化する。

## 背景

- 「飛躍し始める直前」の企業では、売上増加率に対して営業利益増加率が加速する（営業レバレッジが効く）パターンがよく見られる
- 営業レバレッジが高い企業は、売上拡大期に大きな利益成長が期待でき、スクリーニング条件として有用
- 既存のYoYデータ（revenue_yoy, operating_income_yoy）を使えば追加データ取得なしで算出可能

## 実装内容

### FinancialMetricへのメソッド追加

- `FinancialMetric.get_operating_leverage_metrics(growth_metrics)` クラスメソッド
  - 営業レバレッジ = operating_income_yoy / revenue_yoy
  - revenue_yoyが0またはnilの場合はnilを返す
  - revenue_yoyが極端に小さい場合（abs < 0.01）もnilとする（分母が小さすぎて不安定）

### data_jsonへの格納

- `financial_metrics.data_json` に格納する
- キー名: `operating_leverage`

### 活用例

- 営業レバレッジ > 2.0 の企業 = 売上成長が利益に倍以上の影響を与える（固定費型ビジネス）
- 営業レバレッジの推移を見ることで、固定費の吸収が進んでいるかを判断
- セクター分析と組み合わせて、業種ごとの平均営業レバレッジとの比較が可能

### CalculateFinancialMetricsJobへの組み込み

- 既存の `calculate_metrics_for(fv)` 内で、growth_metricsの算出後に `get_operating_leverage_metrics` を呼び出す
- 結果を `data_json` にマージして保存

## テスト

- `get_operating_leverage_metrics` のユニットテスト
  - 正常ケース: revenue_yoy=0.1, operating_income_yoy=0.3 → operating_leverage=3.0
  - revenue_yoyが0の場合にnilを返すこと
  - revenue_yoyが極端に小さい場合にnilを返すこと
  - revenue_yoyまたはoperating_income_yoyがnilの場合にnilを返すこと
  - 負のレバレッジ（売上増・利益減）のケース

## 依存関係

- なし（既存のgrowth_metricsの値のみ使用）
- CalculateFinancialMetricsJobの拡張として組み込む
