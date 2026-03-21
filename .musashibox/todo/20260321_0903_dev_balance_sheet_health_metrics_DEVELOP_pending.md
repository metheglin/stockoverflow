# Balance Sheet Health Metrics（財務健全性指標）

## 概要

FinancialMetricに貸借対照表ベースの財務健全性指標を追加する。
現在、収益性（ROE, ROA, 利益率）やCF指標は計算されているが、財務の安全性・健全性を示す指標が不足している。
企業のスクリーニングにおいて「財務が健全である」ことの判定に不可欠な指標群を実装する。

## 背景

- FinancialValueには `total_assets`, `net_assets`, `equity_ratio`（固定カラム）、`current_assets`, `noncurrent_assets`, `current_liabilities`, `noncurrent_liabilities`, `shareholders_equity`（data_json）が存在
- これらの値から安全性指標を計算し、FinancialMetricの data_json に格納する

## 実装する指標

### FinancialMetric.data_json への追加フィールド

1. **debt_equity_ratio** (D/Eレシオ)
   - 計算: (total_assets - net_assets) / net_assets
   - 意味: 自己資本に対する負債の比率。低いほど安全

2. **current_ratio** (流動比率)
   - 計算: current_assets / current_liabilities
   - 意味: 短期的な支払能力。1.0以上が望ましい
   - ※ EDINET XBRLデータがある場合のみ計算可能

3. **equity_ratio_calculated** (自己資本比率)
   - 計算: net_assets / total_assets
   - 意味: JQUANTSの equity_ratio と一致するはずだが、検証・補完用
   - ※ JQUANTSにequity_ratioがあればそちらを優先

4. **net_debt** (ネット有利子負債)
   - 計算: (total_assets - net_assets) - cash_and_equivalents
   - 意味: 負のとき実質無借金

5. **net_debt_positive** (Boolean)
   - ネット有利子負債がプラス（実質有利子負債あり）かどうか

## 技術的注意点

- CalculateFinancialMetricsJob 内の既存メソッドに追加する形で実装
- data_json のスキーマ定義に新フィールドを追加
- current_assets/current_liabilities はEDINETデータがない企業では計算不可。その場合はnilとする
- テストは FinancialMetric のメソッド単位で記述
