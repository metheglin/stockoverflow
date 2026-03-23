# ROIC・資本効率指標の実装

## 概要

ROIC（投下資本利益率）を中心とした資本効率指標をFinancialMetricのdata_jsonに追加する。
ROEやROAとは異なる視点で経営の質を評価するための指標群。

## 背景

- ROEは財務レバレッジで嵩上げ可能だが、ROICは事業そのものの資本効率を測定する
- 既存の DuPont ROE分解 TODO はROEの因数分解であり、ROICとは分析の目的が異なる
- 「業績が飛躍し始める直前の変化」を捉えるため、ROICの推移トレンドは有力なシグナル

## 実装内容

### 指標

1. **ROIC (Return on Invested Capital)**
   - 算出: NOPAT / 投下資本
   - NOPAT = 営業利益 × (1 - 実効税率)
     - 実効税率は (法人税等 / 税引前利益) で推定。data_json拡張 or デフォルト30%
   - 投下資本 = 純資産 + 有利子負債 - 現預金
     - 有利子負債は (total_assets - net_assets) で概算可能
     - 将来的にEDINET XBRLから有利子負債の正確な値が取得できれば精度向上

2. **ROIC Spread**
   - 算出: ROIC - WACC（推定値）
   - WACCは簡易推定（株主資本コスト=期待リターン8%固定、負債コスト=1%固定など）
   - 正の ROIC Spread → 価値創造

3. **投下資本回転率**
   - 算出: net_sales / 投下資本
   - 資産回転率と合わせて比較

4. **NOPAT Margin**
   - 算出: NOPAT / net_sales
   - 営業利益率の税引後版

### 実装箇所

- `FinancialMetric` に `get_roic_metrics(fv, stock_price: nil)` クラスメソッドを追加
- `data_json` に `roic`, `roic_spread`, `invested_capital_turnover`, `nopat_margin` を格納
- `CalculateFinancialMetricsJob` でメトリクス算出時に併せて算出

### テスト

- ROIC算出のロジックテスト（正常値、nil安全性）
- NOPAT計算の税率推定テスト
- 投下資本のゼロ・マイナスケースのハンドリング

## 依存

- 既存の `financial_values` テーブル（営業利益、純資産、total_assets、net_sales）
- 有利子負債の正確な値は `plan_edinet_xbrl_enrichment` 完了後に精度向上
- 税率推定は概算で開始し、XBRL拡張後に改善可能
