# 複合財務スコアリングシステム実装

## 概要

個別の財務指標（成長率、収益性、CF健全性、バリュエーション等）を統合し、複合スコアとして企業をランキング可能にする。「注目すべき企業を一覧できるようなシステム」というプロジェクト目標を直接支援する機能。

## 背景

現在 `financial_metrics` には以下の指標群が計算済み:
- 成長性: revenue_yoy, operating_income_yoy, net_income_yoy, eps_yoy, consecutive_revenue_growth, consecutive_profit_growth
- 収益性: roe, roa, operating_margin, ordinary_margin, net_margin
- CF: free_cash_flow, operating_cf_positive, investing_cf_negative
- バリュエーション: per, pbr, psr, dividend_yield, ev_ebitda

これらを個別に見るだけでなく、複合的に評価することで、多面的に優れた企業を効率的に発見できる。

## 実装内容

### 1. FinancialMetric にスコア計算メソッド追加

以下の複合スコアをクラスメソッドとして実装する。各スコアは 0〜100 の範囲で正規化。

#### Growth Score（成長性スコア）
入力指標:
- `revenue_yoy` (重み: 25%)
- `operating_income_yoy` (重み: 25%)
- `eps_yoy` (重み: 20%)
- `consecutive_revenue_growth` (重み: 15%)
- `consecutive_profit_growth` (重み: 15%)

#### Quality Score（質スコア）
入力指標:
- `roe` (重み: 25%)
- `operating_margin` (重み: 25%)
- `operating_cf_positive` + `investing_cf_negative` (重み: 20%)
- `free_cash_flow > 0` (重み: 15%)
- `roa` (重み: 15%)

#### Value Score（割安度スコア）
入力指標:
- `per` の逆数（低PERが高スコア）(重み: 30%)
- `pbr` の逆数（低PBRが高スコア）(重み: 30%)
- `ev_ebitda` の逆数 (重み: 20%)
- `dividend_yield` (重み: 20%)

#### Composite Score（総合スコア）
- Growth Score (重み: 35%)
- Quality Score (重み: 40%)
- Value Score (重み: 25%)

### 2. スコア計算の設計方針

- `get_growth_score(metric)` のようにクラスメソッドとして定義
- 各指標は percentile rank（全企業中の相対位置）で 0〜100 に正規化する方式を採用
- percentile 計算は全企業の同期間メトリクスを母集団とする
- NULL 値の指標は当該項目のウェイトを除外して再配分

### 3. data_json スキーマ拡張

`financial_metrics.data_json` に以下を追加:
- `growth_score`: Float
- `quality_score`: Float
- `value_score`: Float
- `composite_score`: Float

### 4. CalculateFinancialMetricsJob への統合

- 全企業の metrics 計算完了後、バッチ処理でスコアを算出
- percentile 計算のため、全企業分のデータが必要（個別計算ではなくバッチ）

### 5. テスト

- 各スコア計算メソッドのユニットテスト
- NULL 値がある場合のウェイト再配分テスト
- 境界値テスト（全指標が同値の場合等）

## 注意事項

- スコアの重みは定数として定義し、将来的な調整を容易にする
- percentile 計算はセクター別に実施するオプションも将来的に検討（セクター内順位）
- 赤字企業やデータ不足企業はスコア算出対象外とするか、ペナルティを付与するか方針を決定する必要あり
