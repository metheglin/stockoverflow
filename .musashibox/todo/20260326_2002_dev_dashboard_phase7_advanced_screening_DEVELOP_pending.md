# DEVELOP: ダッシュボード Phase 7 - 高度なスクリーニング（複数期間条件）

## 概要

ダッシュボードの検索機能に「時間軸をまたぐ条件」を追加し、「直近5年中4年以上ROE > 10%」「営業利益率が3年連続改善」のようなスクリーニングを可能にする。

## 背景

現在のConditionExecutorはpoint-in-time条件（最新期の値でフィルタ）のみ対応。プロジェクトの主要ユースケースは本質的に時間軸を含むため、この機能は検索ダッシュボードの価値を飛躍的に高める。

- 「6期連続増収増益」→ `consecutive_revenue_growth >= 6` で対応可能だが、他の指標では連続性条件が使えない
- 「ROE > 10%を直近5年中4年以上達成」→ 現在不可能
- 「FCFがマイナスからプラスに転換」→ ビルトインプリセットで一部対応済みだが、汎用的な転換検出は不可能

## 前提・依存

- Phase 2（検索バックエンド: ConditionExecutor）が完了していること（完了済み）
- Phase 3（検索フロントエンド: フィルタビルダー）が完了していること（完了済み）
- Phase 6（データエンリッチメント）は推奨だが必須ではない

## 参照する既存TODO

- `20260321_1203_dev_multi_period_screening_conditions_DEVELOP_pending.md` — MultiPeriodScreeningQueryの仕様

---

## Part 1: MultiPeriodConditionEvaluator（バックエンド）

### 1-1. 新クラス: ScreeningPreset::MultiPeriodConditionEvaluator

`app/models/screening_preset/multi_period_condition_evaluator.rb`

既存のConditionExecutorのポストフィルタとして組み込む設計。ConditionExecutorでまず最新期条件で絞り込み、その結果に対して時間軸条件を適用する。

```ruby
class ScreeningPreset::MultiPeriodConditionEvaluator
  TEMPORAL_TYPES = %w[
    at_least_n_of_m
    consecutive
    improving
    deteriorating
    transition_positive
    transition_negative
  ].freeze

  # 対象の metric フィールド（FinancialMetric の固定カラム + data_json フィールド）
  METRIC_FIELDS = %w[
    roe roa operating_margin net_margin
    revenue_yoy operating_income_yoy net_income_yoy eps_yoy
    free_cf_positive operating_cf_positive
  ].freeze

  # @param company_ids [Array<Integer>] 対象企業ID（事前フィルタ済み）
  # @param conditions [Array<Hash>] 時間軸条件の配列
  # @param scope_type [String] "consolidated" or "non_consolidated"
  # @param period_type [String] "annual" etc.
  def initialize(company_ids:, conditions:, scope_type: "consolidated", period_type: "annual")
  end

  # 全条件を満たす企業IDの配列を返す
  # @return [Array<Integer>]
  def execute
  end
end
```

### 1-2. 条件JSONフォーマット

```json
{
  "type": "temporal",
  "temporal_type": "at_least_n_of_m",
  "field": "roe",
  "threshold": 0.10,
  "comparison": "gte",
  "n": 4,
  "m": 5
}
```

```json
{
  "type": "temporal",
  "temporal_type": "consecutive",
  "field": "operating_margin",
  "direction": "improving",
  "n": 3
}
```

```json
{
  "type": "temporal",
  "temporal_type": "transition_positive",
  "field": "free_cf_positive"
}
```

### 1-3. 条件評価メソッド

```ruby
# 企業の履歴データが時間軸条件を満たすか判定
# @param metrics_history [Array<FinancialMetric>] fiscal_year_end降順
# @param condition [Hash] 時間軸条件
# @return [Boolean]
def evaluate_temporal_condition(metrics_history, condition)
end
```

各temporal_typeの評価ロジック:

- `at_least_n_of_m`: 直近M期分のmetricを取得し、threshold以上/以下の期がN期以上あるか
- `consecutive`: 直近N期分が連続して改善(improving)/悪化(deteriorating)しているか
- `improving`: 直近N期分でフィールド値が全て前期より上昇しているか
- `deteriorating`: 直近N期分でフィールド値が全て前期より下降しているか
- `transition_positive`: 前期false → 当期true（booleanフィールド用）
- `transition_negative`: 前期true → 当期false（booleanフィールド用）

### 1-4. パフォーマンス戦略

- 事前にConditionExecutorのpoint-in-time条件で対象企業を絞り込む（通常数十〜数百社）
- 絞り込み済みの企業IDに対してのみ履歴データをバッチロード
- `FinancialMetric.where(company_id: target_ids, scope: scope_type, period_type: period_type).order(:company_id, :fiscal_year_end)` で一括取得
- Rubyで `group_by(&:company_id)` してから各企業の履歴を評価

---

## Part 2: ConditionExecutor への統合

### 2-1. conditions_json の拡張

ConditionExecutorが認識するconditionタイプに `temporal` を追加:

```ruby
# ConditionExecutor#apply_conditions 内で
when "temporal"
  # temporal条件は収集のみし、ポストフィルタで適用
  @temporal_conditions << condition
```

### 2-2. ポストフィルタでの適用

`execute` メソッド内で、既存のポストフィルタ（data_json_range, metric_top_n, preset_ref）の後に temporal 条件を適用:

```ruby
def execute
  results = build_and_filter_results  # 既存処理

  if @temporal_conditions.any?
    company_ids = results.map { |r| r[:company].id }
    evaluator = MultiPeriodConditionEvaluator.new(
      company_ids: company_ids,
      conditions: @temporal_conditions,
      scope_type: @scope_type,
      period_type: @period_type,
    )
    passing_ids = evaluator.execute.to_set
    results = results.select { |r| passing_ids.include?(r[:company].id) }
  end

  apply_sort_and_limit(results)
end
```

---

## Part 3: ダッシュボードUI統合

### 3-1. フィルタビルダー拡張

`filter_builder_controller.js` に時間軸条件タイプを追加:

条件タイプセレクターに「時間軸条件」を追加:
```html
<option value="temporal">時間軸条件</option>
```

temporal が選択された場合のUI:
1. temporal_type セレクター: 「N期中M期達成」「N期連続」「改善中」「悪化中」「プラス転換」「マイナス転換」
2. field セレクター: ROE, ROA, 営業利益率, 売上YoY, FCF正/負 等
3. threshold 入力（at_least_n_of_m, consecutive の場合）
4. n, m 入力（at_least_n_of_m の場合）/ n 入力（consecutive の場合）

### 3-2. condition_row パーシャル拡張

`search/_condition_row.html.erb` に temporal 用のフォーム要素を追加。temporal_type の選択に応じて表示する入力フィールドを動的に切り替える。

### 3-3. ビルトインプリセット追加

`db/seeds/screening_presets.rb` に時間軸条件を含むプリセットを追加:

- 「安定高ROE（5年中4年以上 ROE > 10%）」
- 「営業利益率3年連続改善」
- 「フリーCFプラス転換（直近1年）」

---

## テスト

### MultiPeriodConditionEvaluator テスト

`spec/models/screening_preset/multi_period_condition_evaluator_spec.rb`

- `#evaluate_temporal_condition`:
  - `at_least_n_of_m`: 5期中4期ROE > 10% を達成する企業が条件を満たすこと
  - `at_least_n_of_m`: 5期中3期しか達成しない企業が条件を満たさないこと
  - `consecutive`: 3期連続改善の企業が条件を満たすこと
  - `consecutive`: 途中で悪化がある企業が条件を満たさないこと
  - `transition_positive`: 前期false→当期trueで条件を満たすこと
  - `transition_positive`: 前期もtrueの場合は条件を満たさないこと
  - 履歴データが不足する場合にfalseとすること
- `#execute`:
  - 複数のtemporal条件が全てAND条件で適用されること
  - 空のcompany_idsに対して空配列を返すこと

### ConditionExecutor統合テスト

既存のcondition_executor_specに temporal 条件のテストを追加:
- temporal 条件と既存条件（metric_range等）の組み合わせ
- temporal 条件のみの場合

---

## ファイル構成

### 新規作成

| ファイル | 内容 |
|---------|------|
| `app/models/screening_preset/multi_period_condition_evaluator.rb` | 時間軸条件評価エンジン |
| `spec/models/screening_preset/multi_period_condition_evaluator_spec.rb` | テスト |

### 変更ファイル

| ファイル | 変更内容 |
|---------|---------|
| `app/models/screening_preset/condition_executor.rb` | temporal条件の認識と MultiPeriodConditionEvaluator への委譲 |
| `app/javascript/controllers/filter_builder_controller.js` | temporal条件タイプのUI追加 |
| `app/views/dashboard/search/_condition_row.html.erb` | temporal用フォーム要素追加 |
| `db/seeds/screening_presets.rb` | 時間軸プリセット追加 |
| `spec/models/screening_preset/condition_executor_spec.rb` | temporal統合テスト追加 |

---

## 実装順序

1. MultiPeriodConditionEvaluator クラス作成（evaluate_temporal_condition メソッド群）
2. テスト作成・実行
3. ConditionExecutor への統合（temporal条件の認識・ポストフィルタ）
4. ConditionExecutor 統合テスト追加
5. フィルタビルダーJS更新（temporal条件UI）
6. condition_row パーシャル更新
7. ビルトインプリセット追加（seed）
8. 全テスト実行
