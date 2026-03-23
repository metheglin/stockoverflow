# DEVELOP: 経営者予想精度プロファイルの構築

## 概要

各企業の経営者業績予想が実績に対してどの程度正確かを、複数期間にわたって追跡・集計し、企業ごとの「予想精度プロファイル」を構築する。既存のsurprise_metricsデータを活用し、予想の偏り（保守的/楽観的）やブレ幅を定量化する。

## 背景

現在、`FinancialMetric.data_json` に `revenue_surprise`, `operating_income_surprise`, `net_income_surprise`, `eps_surprise` が格納されているが、これは各期の単発の乖離率であり、「この企業は歴史的にどれくらい保守的か」「予想のブレ幅はどれくらいか」という企業固有の予想特性は把握できない。

予想精度プロファイルは以下のユースケースに直結する:

- **保守的な予想を出す企業の発見**: 毎期上振れする企業は、予想を控えめに出す傾向がある。こうした企業の新たな業績予想は「実力値はもっと上」と解釈できる
- **飛躍前兆の検出**: 過去に正確だった予想が突然大幅に上振れ始めたとき、企業自身も想定していない成長加速が起きている可能性がある
- **リスク回避**: 常に下振れする企業（楽観的な予想を出す傾向）は要注意

## 実装内容

### 1. FinancialMetric にプロファイル算出メソッドを追加

```ruby
# 企業の予想精度プロファイルを算出する
#
# 同一企業の複数期にわたる surprise_metrics を集計し、
# 予想精度の傾向と一貫性を定量化する。
#
# @param metrics [Array<FinancialMetric>] 同一企業の時系列メトリクス（fiscal_year_end昇順）
# @return [Hash] プロファイル情報
#
# 例:
#   profile = FinancialMetric.get_forecast_accuracy_profile(company_metrics)
#   # => {
#   #   "revenue_surprise_mean" => 0.03,    # 平均: 売上は3%上振れ傾向
#   #   "revenue_surprise_stddev" => 0.05,  # ブレ幅（標準偏差）
#   #   "revenue_surprise_median" => 0.02,
#   #   "revenue_beat_rate" => 0.75,        # 75%の確率で上振れ
#   #   "operating_income_surprise_mean" => 0.08,
#   #   "operating_income_surprise_stddev" => 0.12,
#   #   "operating_income_surprise_median" => 0.06,
#   #   "operating_income_beat_rate" => 0.80,
#   #   "net_income_surprise_mean" => ...,
#   #   "net_income_surprise_stddev" => ...,
#   #   "net_income_surprise_median" => ...,
#   #   "net_income_beat_rate" => ...,
#   #   "forecast_bias" => "conservative",  # conservative / optimistic / neutral
#   #   "forecast_consistency" => "high",    # high / medium / low
#   #   "sample_count" => 5,
#   # }
#
def self.get_forecast_accuracy_profile(metrics)
```

### 2. プロファイル判定ロジック

#### forecast_bias（予想の偏り）

- `conservative`: revenue_surprise_mean > 0.02 かつ operating_income_surprise_mean > 0.02 （恒常的に上振れ）
- `optimistic`: revenue_surprise_mean < -0.02 かつ operating_income_surprise_mean < -0.02 （恒常的に下振れ）
- `neutral`: 上記いずれにも該当しない

#### forecast_consistency（予想の一貫性）

- surprise の標準偏差が小さいほど一貫性が高い
- `high`: revenue_surprise_stddev < 0.05
- `low`: revenue_surprise_stddev > 0.15
- `medium`: その間

#### beat_rate（予想超過率）

- 各指標について、surprise > 0 であった期の割合を算出

### 3. プロファイルの保存先

`FinancialMetric.data_json` に格納する（直近の決算メトリクスに集約値として保存）。
キーにはすべて `forecast_` プレフィクスを付与して、既存のsurprise_metricsと区別する。

### 4. CalculateFinancialMetricsJob への組み込み

- メトリクス算出時に、同一企業のsurprise_metricsが格納された過去のFinancialMetricを取得
- 最低3期分のsurpriseデータがある場合にプロファイルを算出
- 算出結果を最新期のFinancialMetric.data_jsonにマージ

## テスト

### FinancialMetric

- `.get_forecast_accuracy_profile`:
  - 正常系: 5期分のsurpriseデータから各統計量が正しく算出されること
  - 全期上振れのケースで bias = "conservative" となること
  - 全期下振れのケースで bias = "optimistic" となること
  - surpriseデータがnilの期が混在する場合にnilを除外して算出されること
  - 3期未満の場合に空Hashを返すこと
  - beat_rateが正しく算出されること（上振れ3/5期 → 0.6）
  - stddevによるconsistency判定が正しいこと

## 成果物

- `app/models/financial_metric.rb` - `get_forecast_accuracy_profile` メソッド追加 + data_json スキーマ拡張
- `app/jobs/calculate_financial_metrics_job.rb` - プロファイル算出の組み込み
- `spec/models/financial_metric_spec.rb` - テスト追加

## 依存関係

- 既存のsurprise_metricsが算出済みであることが前提
- forecast_revision_tracking（予想修正追跡）とは独立して実装可能（本TODOは実績との乖離の統計分析、予想修正追跡は期中の修正履歴の保持）
