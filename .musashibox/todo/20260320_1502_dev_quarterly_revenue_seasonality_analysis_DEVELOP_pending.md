# DEVELOP: 四半期売上季節性分析メトリクスの実装

## 概要

四半期別の売上・利益の構成比パターンを分析し、企業ごとの売上季節性と収益予測可能性を定量化する。四半期ごとの貢献度偏りを検出し、業績の「偏り」と「安定性」をスクリーニング指標として活用可能にする。

## 背景

既存の `dev_quarterly_yoy_comparison` TODOは「同一四半期の前年同期比」（Q1 2025 vs Q1 2024）を扱うが、同一年度内の四半期間の構成比（Q1:Q2:Q3:Q4の比率）は分析対象にしていない。

四半期季節性分析は以下のユースケースに有用:

- **Q4偏重企業の検出**: 年度末に売上が集中する企業は、期末に大型案件を計上するパターンが多く、利益の質に疑問がある場合がある
- **安定収益企業のスクリーニング**: 四半期間で均等な売上配分の企業はストック型ビジネスの可能性が高く、業績の予測可能性が高い
- **異常四半期の検出**: 過去の季節性パターンから大きく逸脱した四半期は、何らかの構造変化やイベントを示唆する

## 前提

- FinancialValue に `period_type` が q1/q2/q3/annual として格納されている
- q1/q2/q3 は累計値（Q1=Q1単独、Q2=Q1+Q2累計、Q3=Q1+Q2+Q3累計）の可能性があるため、差分で各四半期の単独値を算出する必要がある
- annual（通期）- Q3累計 = Q4単独値

## 実装内容

### 1. FinancialMetric に季節性分析メソッドを追加

```ruby
# 四半期売上季節性を分析する
#
# 同一企業・同一fiscal_yearのQ1〜Q4の売上高から
# 四半期ごとの構成比と偏り指標を算出する。
#
# @param annual_fv [FinancialValue] 通期（annual）の財務数値
# @param quarterly_fvs [Array<FinancialValue>] Q1/Q2/Q3の四半期財務数値（period_type昇順）
# @return [Hash] 季節性指標のHash
#
# 例:
#   result = FinancialMetric.get_seasonality_metrics(annual_fv, [q1_fv, q2_fv, q3_fv])
#   # => {
#   #   "q1_revenue_ratio" => 0.20,    # Q1が年間売上の20%
#   #   "q2_revenue_ratio" => 0.25,
#   #   "q3_revenue_ratio" => 0.25,
#   #   "q4_revenue_ratio" => 0.30,    # Q4偏重
#   #   "revenue_concentration_index" => 0.12,  # ハーフィンダール指数ベース (0=完全均等, 高い=偏重)
#   #   "q4_weight" => 1.20,           # Q4の年間平均比 (1.0=均等, >1.0=Q4偏重)
#   #   "max_quarter_ratio" => 0.30,   # 最大四半期の構成比
#   #   "seasonality_stable" => true,  # 前年と比べて構成比パターンが安定しているか
#   # }
def self.get_seasonality_metrics(annual_fv, quarterly_fvs)
```

### 2. 四半期単独値の算出ロジック

```ruby
# 累計値から四半期単独値を算出する
#
# @param quarterly_fvs [Array<FinancialValue>] Q1/Q2/Q3の四半期FV（period_type昇順）
# @param annual_fv [FinancialValue] 通期FV
# @param attribute [Symbol] 算出対象の属性名（:net_sales, :operating_income等）
# @return [Array<Integer/nil>] [Q1単独, Q2単独, Q3単独, Q4単独]
def self.get_standalone_quarterly_values(quarterly_fvs, annual_fv, attribute)
```

- JQUANTS/EDINETの四半期データは累計の場合と単独の場合がある
- 累計の場合: Q2累計 - Q1 = Q2単独、Q3累計 - Q2累計 = Q3単独、年間 - Q3累計 = Q4単独
- 算出値がマイナスになる場合は累計ではなく単独値の可能性があるため、その場合はそのまま使用する

### 3. 偏り指標の算出

#### revenue_concentration_index

正規化ハーフィンダール指数を利用する:
- HHI = Σ(qi^2) ここで qi は各四半期の構成比
- 完全均等（各25%）の場合 HHI = 0.25
- 正規化: (HHI - 0.25) / 0.75 → 0 = 完全均等, 1 = 1四半期に集中

#### q4_weight

Q4の構成比 / 均等配分（0.25）で算出。日本企業の決算は3月末が多く、Q4（1-3月）に売上が集中する傾向がある。1.0を超える企業はQ4偏重。

### 4. data_json スキーマ拡張

`FinancialMetric.data_json` に以下を追加（通期メトリクスにのみ格納）:

```ruby
q1_revenue_ratio: { type: :decimal },
q2_revenue_ratio: { type: :decimal },
q3_revenue_ratio: { type: :decimal },
q4_revenue_ratio: { type: :decimal },
revenue_concentration_index: { type: :decimal },
q4_weight: { type: :decimal },
```

### 5. CalculateFinancialMetricsJob への組み込み

- `calculate_metrics_for(fv)` で `fv.period_type == "annual"` の場合にのみ実行
- 同一企業・同一fiscal_year・同一scopeのQ1/Q2/Q3を取得して `get_seasonality_metrics` を呼び出す
- Q1/Q2/Q3のうち1つでも欠けている場合は算出しない

## テスト

### FinancialMetric

- `.get_seasonality_metrics`:
  - 正常系: 均等配分のケースで concentration_index ≈ 0, q4_weight ≈ 1.0 となること
  - Q4偏重ケースで q4_revenue_ratio が高く q4_weight > 1.0 となること
  - Q1/Q2/Q3のいずれかがnil（データ欠損）の場合に空Hashを返すこと
- `.get_standalone_quarterly_values`:
  - 累計値から正しく単独値が算出されること
  - 差分がマイナスになる場合（単独値がそのまま格納されているケース）に単独値として扱われること

## 成果物

- `app/models/financial_metric.rb` - `get_seasonality_metrics`, `get_standalone_quarterly_values` メソッド追加 + data_json スキーマ拡張
- `app/jobs/calculate_financial_metrics_job.rb` - 季節性算出の組み込み
- `spec/models/financial_metric_spec.rb` - テスト追加

## 依存関係

- 四半期データ（period_type = q1/q2/q3）が取り込まれていることが前提
- `dev_quarterly_yoy_comparison` とは独立して実装可能（本TODOは同一年度内の構成比分析、そちらは前年同期比較）
