# bugfix: 四半期累計値による指標計算の歪み

## 概要

JQUANTS / EDINET から取得する四半期データ（period_type: q1, q2, q3）の損益計算書・キャッシュフロー計算書の値は累計値であるが、CalculateFinancialMetricsJob はこれを単一期間の値として扱い、収益性指標（ROE, ROA, 営業利益率等）を計算している。これにより四半期ベースの指標が系統的に歪む。

## 背景

JQUANTSの財務サマリーデータにおける四半期データ:
- Q1: 第1四半期（3ヶ月）の累計 → 3ヶ月分
- Q2: 第1〜第2四半期（6ヶ月）の累計 → 6ヶ月分
- Q3: 第1〜第3四半期（9ヶ月）の累計 → 9ヶ月分
- annual: 通期（12ヶ月）の累計 → 12ヶ月分

## 問題の影響

1. **ROE/ROAの過小評価**: Q2累計の当期純利益(6ヶ月分) / 総資産 → 通期ROEの約半分の値になる
2. **営業利益率等は正常**: 累計売上高と累計営業利益の比率は正しい（率は月数に依存しない）
3. **四半期間比較の不正確さ**: Q2累計 vs Q1累計のYoYは正しいが、Q2単独の業績は Q2累計 - Q1累計 で算出する必要がある
4. **連続増益カウントへの影響**: 累計値ベースのYoY自体は同期間比較なので正しいが、指標値の絶対水準が歪む

## 修正方針

1. FinancialMetric の収益性指標計算(`get_profitability_metrics`)において、period_type を考慮する
   - ROE / ROA: 四半期累計値の場合、年率換算する（例: Q2の場合 × 12/6）
   - 利益率（operating_margin等）: 累計値同士の比率なので修正不要
2. キャッシュフロー指標も同様に、四半期累計であることを注記または年率換算する
3. FinancialMetric の data_json に `annualized: true/false` を記録し、年率換算済みかどうかを追跡可能にする
4. 将来的な四半期単独値の抽出（Q2単独 = Q2累計 - Q1累計）はスコープ外とし、別TODOで対応

## 関連ファイル

- `app/models/financial_metric.rb` （get_profitability_metrics, get_cf_metrics）
- `app/jobs/calculate_financial_metrics_job.rb` （calculate_metrics_for）
- `app/models/financial_value.rb` （period_type enum）
