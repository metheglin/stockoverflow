# DEVELOP: 指標の安定性・信頼性スコア算出

## 概要

企業の財務指標がどれだけ安定的・一貫的に維持されているかを定量化するスコアを算出する。既存の指標（YoY、トレンド分類等）は変化の方向や大きさを捉えるが、「一貫して高水準を維持しているか」という信頼性の視点が欠けている。これは投資判断の質を左右する重要な要素であり、スクリーニングやスコアリングの基盤指標となる。

## 背景

- 既存のfinancial_metricsはYoY（前年比）と連続期数を計算しているが、「安定性」は測定していない
- `dev_metric_trend_classification` はトレンドの方向性（improving/deteriorating等）に着目しているが、値のばらつき度合いは対象外
- `dev_composite_financial_scores` で利用されるpercentile rankは相対順位であり、安定性とは異なる
- 「6期連続増収増益」で見つかる企業にも、利益率が大きく変動するものと安定しているものがある。後者の方が質の高い成長であり、区別する手段が必要

## 実装内容

### 1. FinancialMetric にクラスメソッド追加

```ruby
# 安定性メトリクスを算出する
#
# @param metrics_history [Array<FinancialMetric>] 同一企業の過去Nの期FinancialMetric（fiscal_year_end昇順）
# @return [Hash] 安定性スコアのHash
#
# 返却例:
#   {
#     roe_cv: 0.15,                  # ROEの変動係数 (coefficient of variation)
#     roe_consistency: 0.8,          # ROE > 閾値を達成した割合 (例: 5期中4期達成 = 0.8)
#     operating_margin_cv: 0.08,
#     operating_margin_consistency: 1.0,
#     revenue_growth_stability: 0.92, # 売上成長率の安定度 (1 - CV, 0-1に正規化)
#     max_drawdown_roe: -0.05,       # ROEの最大下落幅
#     overall_consistency_score: 78,  # 総合安定性スコア (0-100)
#   }
#
def self.get_consistency_metrics(metrics_history)
```

### 2. 算出する指標

#### 変動係数 (CV: Coefficient of Variation)
- 対象指標: ROE, ROA, 営業利益率, 経常利益率, 売上YoY
- 計算: 標準偏差 / 平均値の絶対値
- CVが低いほど安定的
- 平均が0に近い場合は算出不可（nilを返す）

#### 閾値達成率 (Consistency Rate)
- 対象指標と閾値:
  - ROE: 8%, 10%, 15% の各閾値を超えた年度の割合
  - 営業利益率: 5%, 10%, 15%
  - 増収（revenue_yoy > 0）を達成した年度の割合
  - 増益（net_income_yoy > 0）を達成した年度の割合
- 閾値は定数として定義し、将来的な設定変更を容易にする

#### 最大ドローダウン (Max Drawdown)
- 対象指標: ROE, 営業利益率, EPS
- ピーク値からの最大下落幅を計算
- 投資対象の質を評価する上で重要な指標

#### 総合安定性スコア (Overall Consistency Score)
- 上記指標を加重平均して0-100のスコアを算出
- 高スコア = 安定的かつ一貫した財務パフォーマンス

### 3. data_json への格納

- `financial_metrics.data_json` に格納する
- キー名例: `roe_cv`, `roe_consistency_8pct`, `roe_consistency_10pct`, `operating_margin_cv`, `revenue_growth_consistency`, `max_drawdown_roe`, `overall_consistency_score`

### 4. CalculateFinancialMetricsJob への組み込み

- 既存の計算フローの後に安定性スコアを算出
- 最低3期分の履歴データが必要（不足時はnilを設定）
- 5期分のデータがあれば最も信頼性の高いスコアが算出される

## テスト

- `get_consistency_metrics` のユニットテスト
  - 正常ケース: 5期分の安定したデータでCVが低く、consistency rateが高いこと
  - ROEが大きく変動するデータでCVが高くなること
  - 閾値達成率が正しく計算されること
  - 最大ドローダウンが正しく検出されること
  - 履歴が2期分以下の場合にnilが返ること
  - 全期間同一値の場合にCV=0、consistency=1.0であること

## 依存関係

- なし（既存のFinancialMetricのデータのみ使用）
- `dev_composite_financial_scores` がこのスコアを将来的にQuality Scoreの構成要素として利用可能

## 関連TODO

- `dev_metric_trend_classification` - トレンド方向性（本TODOは安定性、相互補完）
- `dev_composite_financial_scores` - 複合スコアの構成要素としての活用
- `dev_metric_percentile_ranking` - パーセンタイル順位と組み合わせたスクリーニング
