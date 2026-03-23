# Altman Z-Score による財務健全性・倒産リスク評価

## 概要

Altman Z-Scoreモデルを実装し、各企業の財務的健全性と倒産リスクを定量評価する。B/S・P/Lの既存データを活用してZ-Scoreを算出し、Safe/Grey/Distressゾーンに分類する。

## 背景

- 既存の財務健全性指標（current ratio, debt-to-equity等）は個別の側面を評価するが、包括的な倒産リスク予測は提供しない
- Z-Scoreは学術的に検証された定量モデルであり、スクリーニングの「除外フィルタ」として有用
- Piotroski F-Score（既存TODO）が「良い企業の発見」なら、Z-Scoreは「危険な企業の排除」を担う

## 実装内容

### FinancialMetric の data_json に追加する項目

- `altman_zscore`: Z-Scoreの値
- `altman_zone`: "safe" (Z > 2.99) / "grey" (1.81 < Z <= 2.99) / "distress" (Z <= 1.81)
- `altman_components`: 各要素の内訳 { x1, x2, x3, x4, x5 }

### 計算ロジック（製造業向けオリジナルモデル）

```
Z = 1.2*X1 + 1.4*X2 + 3.3*X3 + 0.6*X4 + 1.0*X5

X1 = 運転資本 / 総資産 = (current_assets - current_liabilities) / total_assets
X2 = 利益剰余金 / 総資産 = (net_assets - 資本金) / total_assets  ※近似
X3 = EBIT / 総資産 = operating_income / total_assets
X4 = 時価総額 / 負債合計 = (株価 * 発行済株式数) / (total_assets - net_assets)
X5 = 売上高 / 総資産 = net_sales / total_assets
```

### データ要件

- financial_value: total_assets, net_assets, operating_income, net_sales
- financial_value.data_json: current_assets, current_liabilities（EDINET XBRL由来）
- daily_quotes: 時価総額算出用の株価
- current_assets/current_liabilitiesが不足する場合はX1を算出不可とし、Z-Score全体を算出しない

### CalculateFinancialMetricsJob への統合

- 財務健全性指標の一環として計算
- 必要なデータが揃っている企業のみ対象

### テスト

- `get_altman_zscore()` の計算テスト
  - 各ゾーンに分類される既知のテストケース
  - X4の時価総額計算に株価が必要なケースの検証
  - データ欠損時にnilを返すことの確認

## 備考

- 非製造業向けの修正Z-Score (Z'') も将来的に検討可能
- サービス業ではX5（資産回転率）の影響が大きくなるため、セクターごとの解釈が必要
