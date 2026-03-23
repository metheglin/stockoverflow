# Multi-Year CAGR Metrics（複数年CAGR指標）

## 概要

FinancialMetricに複数年にわたるCAGR（年平均成長率）を追加する。
現在、YoY（前年比）は計算されているが、中長期の成長トレンドを把握するための指標が不足している。
3年・5年CAGRを計算することで、一時的な変動を平滑化した「真の成長力」を評価できるようにする。

## 背景

- 6期連続増収増益のスクリーニングは consecutive_revenue_growth/consecutive_profit_growth で可能
- しかし「増収率が高い順」に並べるためには、単年のYoYではなく中長期的な成長率（CAGR）が必要
- CAGR = (end_value / start_value)^(1/n) - 1

## 実装する指標

### FinancialMetric.data_json への追加フィールド

1. **revenue_cagr_3y** (売上高3年CAGR)
   - 3期前のnet_salesと当期のnet_salesからCAGRを計算

2. **revenue_cagr_5y** (売上高5年CAGR)
   - 5期前のnet_salesと当期のnet_salesからCAGRを計算

3. **operating_income_cagr_3y** (営業利益3年CAGR)
4. **operating_income_cagr_5y** (営業利益5年CAGR)

5. **net_income_cagr_3y** (純利益3年CAGR)
6. **net_income_cagr_5y** (純利益5年CAGR)

7. **eps_cagr_3y** (EPS 3年CAGR)
8. **eps_cagr_5y** (EPS 5年CAGR)

## 計算ロジック

- 同一company_id、同一scope、同一period_type(annual)の過去のFinancialValueを参照
- fiscal_year_end を基準に3期前/5期前のレコードを特定
- start_value と end_value がともに正の値の場合のみ計算（赤字→黒字転換などではCAGRは無意味）
- 該当期のデータが存在しない場合はnil

## 技術的注意点

- CalculateFinancialMetricsJob の中で、FinancialValueの過去データへのアクセスが必要
- N+1クエリを避けるため、対象企業の全FinancialValueを事前にロードすることを検討
- CAGRの計算にはRubyの `**` 演算子を使用 (BigDecimal対応)
- period_type は annual のみを対象とする（四半期データのCAGRは意味が薄い）
- テストは FinancialMetric のメソッド単位で記述
