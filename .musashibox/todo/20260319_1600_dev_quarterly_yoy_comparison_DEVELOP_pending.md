# 四半期前年同期比メトリクス実装

## 概要

現在の `FinancialMetric.get_growth_metrics()` は年次YoY（前年同期比）のみを算出しているが、四半期データ（q1/q2/q3）においては前年同四半期との比較が季節性を考慮した本質的な成長率分析となる。四半期別の前年同期比計算ロジックを追加する。

## 背景

- `financial_values` には `period_type` として `annual`, `q1`, `q2`, `q3` が存在する
- 現在の `CalculateFinancialMetricsJob` は前年の同 `scope` + `period_type` のレコードを参照しているため、四半期YoYは部分的に機能している可能性がある
- しかし、四半期固有の比較ロジック（同四半期の検出、累計 vs 単独四半期の識別）が明示的に設計されていない

## 実装内容

### 1. FinancialMetric への四半期比較メソッド追加

- `get_quarterly_yoy_metrics(current_fv, prior_same_quarter_fv)` クラスメソッドを追加
- 四半期累計値から単独四半期値を逆算するロジック（Q2累計 - Q1 = Q2単独）
- 単独四半期ベースでのYoY計算

### 2. CalculateFinancialMetricsJob の拡張

- 四半期レコードの場合、前年同四半期レコードの検索ロジックを明確化
- `fiscal_year_end` が1年前 ± 1ヶ月の範囲で同じ `period_type` のレコードを検索
- 四半期単独値の算出: 前四半期累計値を取得し差分計算

### 3. data_json スキーマ拡張

以下のフィールドを `financial_metrics.data_json` に追加:

- `standalone_quarter_revenue_yoy`: 単独四半期売上YoY
- `standalone_quarter_operating_income_yoy`: 単独四半期営業利益YoY
- `standalone_quarter_net_income_yoy`: 単独四半期純利益YoY

### 4. テスト

- `FinancialMetric.get_quarterly_yoy_metrics()` のユニットテスト
- 累計値からの単独四半期逆算ロジックのテスト
- Q1（前四半期累計が存在しない）のエッジケース

## 注意事項

- 四半期データの「累計」と「単独」の区別は JQUANTS のデータ仕様に依存するため、既存の `FinancialValue` のデータ形式を確認すること
- 前四半期レコードが欠損している場合は単独四半期計算をスキップし、累計ベースのYoYのみ算出する
