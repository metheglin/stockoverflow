# DEVELOP: 複数期間条件スクリーニングの実装

## 概要

現在計画されている `Company::ScreeningQuery` は最新期のpoint-in-time条件（現在のメトリクス値でフィルタ）に対応するが、時間軸をまたぐ条件でのスクリーニングには対応していない。「直近5年中4年以上ROE > 10%」「営業利益率が3年連続改善」のような複数期間にまたがる条件でスクリーニングする機能を実装する。

## 背景

- `dev_analysis_query_layer` の `ScreeningQuery` は最新期の値に対するmin/max/boolean条件のみサポート
- `dev_metric_trend_classification` はトレンド方向のラベルを付与するが、ラベルの元となる期間数を柔軟に変更できない
- `dev_metric_consistency_reliability_score` は安定性スコアを算出するが、任意の条件を組み合わせた柔軟なスクリーニングではない
- プロジェクトの主要ユースケースは本質的に時間軸を含む:
  - 「6期連続増収増益」→ 連続期数は既にサポートされるが、他の条件では未対応
  - 「FCFがマイナスからプラスに転換」→ 状態変化は時間軸の条件
  - 「飛躍する直前の変化」→ 過去数年にわたるパターン

## 実装内容

### 1. Company::MultiPeriodScreeningQuery

**配置先**: `app/models/company/multi_period_screening_query.rb`

```ruby
class Company::MultiPeriodScreeningQuery
  # 時間軸条件の種類
  #
  # :at_least_n_of_m  - 直近M年中N年以上条件を達成
  # :consecutive       - N年連続で条件を達成
  # :improving         - 直近N年間改善し続けている
  # :deteriorating     - 直近N年間悪化し続けている
  # :transition_positive - 直前期まで条件未達→最新期で達成（プラス転換）
  # :transition_negative - 直前期まで条件達成→最新期で未達（マイナス転換）
  TEMPORAL_CONDITIONS = %i[
    at_least_n_of_m consecutive improving deteriorating
    transition_positive transition_negative
  ].freeze

  attr_reader :temporal_filters, :scope_type, :period_type, :limit

  # @param temporal_filters [Array<Hash>] 時間軸条件の配列
  #   各要素:
  #   {
  #     metric: :roe,                    # 対象指標
  #     condition: :at_least_n_of_m,     # 条件種別
  #     threshold: 0.10,                 # 閾値（metric > threshold で達成判定）
  #     n: 4,                            # 達成必要年数
  #     m: 5,                            # 対象期間年数
  #   }
  #   または
  #   {
  #     metric: :operating_margin,
  #     condition: :consecutive,
  #     threshold: 0.0,                  # YoYが0以上 = 改善
  #     n: 3,                            # 3年連続
  #   }
  #   または
  #   {
  #     metric: :free_cf_positive,
  #     condition: :transition_positive,  # false → true への転換
  #   }
  #
  def initialize(temporal_filters:, scope_type: :consolidated, period_type: :annual,
                 sector_33_code: nil, market_code: nil, limit: nil)
  end

  def execute
    # 1. 全上場企業のcompany_idを取得
    # 2. 各企業について直近M期分のFinancialMetricを取得
    # 3. temporal_filtersの全条件を満たす企業のみを結果に含める
    # 4. 結果を返却
  end
end
```

### 2. 条件評価メソッド

```ruby
# 企業の履歴データが時間軸条件を満たすか判定する
#
# @param metrics_history [Array<FinancialMetric>] fiscal_year_end昇順の履歴
# @param filter [Hash] 時間軸条件
# @return [Boolean]
def evaluate_temporal_condition(metrics_history, filter)
```

### 3. パフォーマンス考慮

- 全上場企業（約4,000社）× 直近5-10期のFinancialMetricをメモリにロードする必要がある
- 事前フィルタ: 最新期のpoint-in-time条件で絞り込んでから時間軸条件を評価する
- バッチロード: `FinancialMetric.where(company_id: target_ids).order(:company_id, :fiscal_year_end)` で一括取得し、Rubyでグループ化

### 4. ScreeningQuery との統合

- 既存の `Company::ScreeningQuery` に `temporal_filters` パラメータを追加するか、または独立したQueryObjectとして実装する
- 推奨: 独立したQueryObject として実装し、必要に応じてScreeningQueryと組み合わせて使う

## テスト

- `#evaluate_temporal_condition` のユニットテスト
  - `at_least_n_of_m`: 5期中4期ROE > 10% を達成する企業が条件を満たすこと
  - `at_least_n_of_m`: 5期中3期しか達成しない企業が条件を満たさないこと
  - `consecutive`: 3期連続改善の企業が条件を満たすこと
  - `consecutive`: 途中で悪化がある企業が条件を満たさないこと
  - `transition_positive`: 前期false→当期trueで条件を満たすこと
  - `transition_positive`: 前期もtrueの場合は条件を満たさないこと
  - 履歴データが不足する場合に条件を満たさない（false）とすること
- `#execute` の結合テスト
  - 複数のtemporal_filtersが全てAND条件で適用されること

## 依存関係

- `dev_analysis_query_layer` のFinancialMetric scopeの一部を利用
- 独立して実装可能（FinancialMetricモデルの既存カラムのみ使用）

## 関連TODO

- `dev_analysis_query_layer` - point-in-timeスクリーニング（本TODOが時間軸拡張）
- `dev_metric_trend_classification` - トレンドラベル（本TODOはラベルではなく条件ベースの柔軟な判定）
- `dev_metric_consistency_reliability_score` - 安定性スコア（相互補完的に使用可能）
- `plan_screening_state_change_detection` - 状態変化検出（transition条件との親和性）
