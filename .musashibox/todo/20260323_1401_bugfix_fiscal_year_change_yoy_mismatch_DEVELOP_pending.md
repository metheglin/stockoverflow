# bugfix: 決算期変更企業のYoY計算ミスマッチ

## 概要

CalculateFinancialMetricsJob の `find_previous_financial_value` は、fiscal_year_end の1年前 ±1ヶ月の範囲で前期の FinancialValue を検索するが、決算期変更を行った企業では変則決算期（9ヶ月/15ヶ月等）のレコードが前期として誤マッチし、YoY指標が不正確になる。

## 背景

- 日本の上場企業は3月期決算が多数だが、12月期・6月期・9月期なども存在する
- 企業が決算期を変更した場合（例: 3月期 → 12月期）、変則決算期間が発生する
- 変則期間の売上高や利益は通常12ヶ月と比較不可能（9ヶ月 vs 12ヶ月で-25%になるなど）

## 問題の影響

1. 変則決算期のYoYが異常値（-25%〜+33%など）になり、増収増益/減収減益の判定を誤る
2. `consecutive_revenue_growth` / `consecutive_profit_growth` が変則期間でリセットまたは不正にカウントされる
3. スクリーニングで「6期連続増収増益」に該当する企業が漏れたり、非該当企業が含まれる

## 修正方針

1. FinancialValue に `period_months` カラム（または data_json 属性）を追加し、その会計期間が何ヶ月分かを記録する
   - JQUANTS: period_start / period_end から計算、または fiscal_year_start / fiscal_year_end から推定
   - EDINET: XBRL の periodStart / periodEnd から計算
2. `find_previous_financial_value` で前期候補を見つけた後、period_months が12でない場合にフラグを立てる
3. YoY計算時に period_months が異なる場合、月数按分（annualize）するか、計算をスキップして nil を返す
4. FinancialMetric に `comparable` (boolean) フラグを追加し、変則期間由来の指標をスクリーニングから除外可能にする

## 関連ファイル

- `app/jobs/calculate_financial_metrics_job.rb` （find_previous_financial_value）
- `app/models/financial_metric.rb` （get_growth_metrics, get_consecutive_metrics）
- `app/models/financial_value.rb` （period_months の追加）
