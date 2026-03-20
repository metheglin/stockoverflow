# Piotroski F-Score 計算の実装

## 概要

Piotroski F-Score（0〜9点のスコアリングシステム）をFinancialMetricのdata_jsonに追加する。
バリュー投資において広く使われる財務健全性のスコアリングであり、既存のfinancial_valuesデータから算出可能。

## 背景

- プロジェクトの目標「注目すべき企業を一覧できるシステム」において、財務健全性の定量化は不可欠
- F-Scoreは9つの明確な基準（各1点）でスコアを算出するため、解釈が容易で透明性が高い
- 既存の composite_financial_scores TODO（独自0-100スコア）とは異なり、学術的に確立された基準を使用

## 実装内容

### F-Scoreの9基準

**収益性 (4点)**
1. 当期純利益 > 0 → 1点
2. ROA > 0 → 1点
3. 営業キャッシュフロー > 0 → 1点
4. 営業キャッシュフロー > 当期純利益（アクルーアルの質） → 1点

**レバレッジ・流動性 (3点)**
5. 長期負債比率が前期より減少（total_assets - net_assetsで代替可） → 1点
6. 流動比率が前期より上昇（data_json拡張で current_assets / current_liabilities） → 1点
7. 新株発行なし（shares_outstanding が前期以下） → 1点

**営業効率 (2点)**
8. 粗利率が前期より上昇（data_json.gross_profit / net_salesで算出） → 1点
9. 資産回転率が前期より上昇（net_sales / total_assets） → 1点

### 実装箇所

- `FinancialMetric` に `get_piotroski_fscore(current_fv, previous_fv, current_metric, previous_metric)` クラスメソッドを追加
- 各基準を個別に判定する内部メソッドを実装し、テストしやすくする
- `data_json` に `piotroski_fscore`（整数 0-9）および `piotroski_detail`（各基準のtrue/false Hash）を格納
- `CalculateFinancialMetricsJob` でメトリクス算出時にF-Scoreも併せて算出

### テスト

- 各基準の判定ロジックを個別にテスト
- 9点満点のケースとエッジケース（nil値が多い場合など）をテスト
- 前期データが存在しない場合のハンドリング

## 依存

- 既存の `financial_values` テーブルのデータ
- EDINET XBRLの拡張データ（gross_profit, current_assets, current_liabilities）があるとより精度が高い
- `plan_edinet_xbrl_enrichment` で取得予定のデータがあれば精度向上するが、なくても算出可能
