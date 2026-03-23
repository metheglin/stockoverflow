# CAGR・複数年成長率メトリクスの実装

## 概要

現在のFinancialMetricはYoY（前年比）のみを計算しているが、プロジェクトの目的である「数年にわたる成長トレンドの把握」には、CAGR（年平均成長率）や複数年間の成長率を算出する仕組みが必要である。

## 背景

- 「6期連続増収増益の企業を一覧し、増収率が高い順に並べる」というユースケースにおいて、YoYだけでは成長の「勢い」を比較しにくい
- 3年CAGR、5年CAGRなど複数の時間軸で成長率を比較できれば、一時的な急成長と持続的な成長を区別できる
- 企業の「飛躍し始める直前」を検出するには、CAGRの加速度（CAGRの変化率）も有用

## 実装内容

### FinancialMetricへのメソッド追加

- `FinancialMetric.get_cagr_metrics(current_fv, historical_fvs)` クラスメソッド
  - `historical_fvs` は同一company_id・同一scope・同一period_typeの過去のFinancialValueの配列
  - CAGR計算対象: net_sales, operating_income, net_income, eps
  - CAGR = (終了値 / 開始値)^(1/年数) - 1
  - 開始値が0以下の場合はnilを返す（対数計算不可）
  - 計算結果をHashで返す: `{ revenue_cagr_3y: 0.15, revenue_cagr_5y: 0.12, ... }`

### data_jsonへの格納

- 計算結果は `financial_metrics.data_json` に格納する
- キー名: `revenue_cagr_3y`, `revenue_cagr_5y`, `operating_income_cagr_3y`, `operating_income_cagr_5y`, `net_income_cagr_3y`, `net_income_cagr_5y`, `eps_cagr_3y`, `eps_cagr_5y`

### CalculateFinancialMetricsJobへの組み込み

- 既存の `calculate_metrics_for(fv)` メソッド内で、同一企業の過去のFinancialValueを取得し `get_cagr_metrics` を呼び出す
- 過去データが不足する場合（3年分未満など）は該当するCAGRをnilとする

### CAGR加速度の算出（オプション）

- 直近3年CAGRと、その3年前の3年CAGRを比較して加速度を算出
- `cagr_acceleration_revenue = revenue_cagr_3y(current) - revenue_cagr_3y(3年前)`
- 「成長率が加速し始めた企業」のスクリーニングに有用

## テスト

- `get_cagr_metrics` のユニットテスト
  - 正常ケース: 3年分・5年分のデータがある場合
  - 開始値が0の場合にnilを返すこと
  - 開始値が負の場合にnilを返すこと
  - データ不足（2年分しかない場合）に該当CAGRがnilであること
  - 全期間同一値の場合にCAGR=0であること

## 依存関係

- なし（既存のFinancialMetricとFinancialValueのみ使用）
- CalculateFinancialMetricsJobの拡張として組み込む
