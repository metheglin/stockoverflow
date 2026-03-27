# DEVELOP: ダッシュボード Phase 6 - データエンリッチメント（トレンド分類・成長加速度）

## 概要

ダッシュボードの企業詳細画面と検索機能を大幅に強化するため、FinancialMetricのdata_jsonに「成長加速度」と「トレンド分類」の2つの指標群を追加し、ダッシュボードUIに統合する。

## 背景

Phase 1-5でダッシュボードの基本機能（企業一覧・詳細・検索・比較）は完成したが、表示されるデータは既存の財務数値・YoY・スコアに限定されている。ユーザーが最も関心を持つ「この企業は今どういう方向に向かっているのか」「成長は加速しているのか減速しているのか」に答える指標が不足している。

## 前提・依存

- Phase 1-5（ダッシュボード基盤）が完了していること（完了済み）
- CalculateFinancialMetricsJob が稼働していること（完了済み）

## 参照する既存TODO

- `20260320_2001_dev_growth_acceleration_metrics_DEVELOP_pending.md` — 成長加速度のバックエンド仕様
- `20260320_1602_dev_metric_trend_classification_DEVELOP_pending.md` — トレンド分類のバックエンド仕様

上記TODOの仕様を基盤として、本TODOではバックエンド実装＋ダッシュボードUI統合の両方を実施する。

---

## Part 1: 成長加速度メトリクス（バックエンド）

### 1-1. data_json スキーマ拡張

`FinancialMetric.define_json_attributes` に以下を追加:

```ruby
revenue_growth_acceleration: { type: :decimal },
operating_income_growth_acceleration: { type: :decimal },
net_income_growth_acceleration: { type: :decimal },
eps_growth_acceleration: { type: :decimal },
acceleration_consistency: { type: :string },  # "accelerating" | "decelerating" | "mixed"
```

### 1-2. 算出メソッド

`FinancialMetric` にクラスメソッドを追加:

```ruby
# 当期YoYと前期YoYの差分を算出
# @param current_metric [FinancialMetric]
# @param previous_metric [FinancialMetric]
# @return [Hash] 加速度メトリクスのHash
def self.get_growth_acceleration_metrics(current_metric, previous_metric)
```

```ruby
# 直近2-3期の加速度の符号一貫性を判定
# @param current_metric [FinancialMetric]
# @param previous_metrics [Array<FinancialMetric>]
# @return [String, nil] "accelerating" | "decelerating" | "mixed" | nil
def self.get_acceleration_consistency(current_metric, previous_metrics)
```

### 1-3. CalculateFinancialMetricsJob への組み込み

既存の前期FinancialMetric取得処理を利用し、メトリクス算出後にgrowth_acceleration_metricsをdata_jsonに追加保存する。2期以上前の取得が必要な場合は追加のクエリを実行する。

---

## Part 2: トレンド分類（バックエンド）

### 2-1. data_json スキーマ拡張

```ruby
# 各指標のトレンド分類ラベル
trend_revenue: { type: :string },
trend_operating_income: { type: :string },
trend_net_income: { type: :string },
trend_eps: { type: :string },
trend_operating_margin: { type: :string },
trend_roe: { type: :string },
trend_roa: { type: :string },
trend_free_cf: { type: :string },
```

ラベル値: `improving` | `deteriorating` | `stable` | `turning_up` | `turning_down` | `volatile`

### 2-2. 算出メソッド

```ruby
# 指標の履歴データからトレンド分類を判定
# @param metric_history [Array<Numeric, nil>] 直近3期分の値（新→旧順）
# @param stability_threshold [Float] 変化率がこの範囲内なら stable（デフォルト: 0.05）
# @return [String, nil] トレンドラベル
def self.classify_trend(metric_history, stability_threshold: 0.05)
```

### 2-3. 分類ロジック

```
3期分の値を [current, previous, two_periods_ago] とする:

change_1 = current vs previous の方向（正=改善、負=悪化）
change_2 = previous vs two_periods_ago の方向

if change_1 > threshold AND change_2 > threshold → "improving"
if change_1 < -threshold AND change_2 < -threshold → "deteriorating"
if |change_1| <= threshold AND |change_2| <= threshold → "stable"
if change_1 > threshold AND change_2 < -threshold → "turning_up"
if change_1 < -threshold AND change_2 > threshold → "turning_down"
else → "volatile"
```

ただし free_cf は正負反転ベースで判定。

### 2-4. CalculateFinancialMetricsJob への組み込み

前期・前々期のFinancialMetricを取得し、各指標のトレンドを分類してdata_jsonに保存する。

---

## Part 3: ダッシュボードUI統合

### 3-1. 企業詳細 - サマリーカード拡張

`companies/_summary_cards.html.erb` にトレンドバッジを追加:
- 各主要指標カード（売上高、営業利益、ROE等）の横にトレンドラベルをバッジ表示
- improving → 緑の上矢印バッジ
- deteriorating → 赤の下矢印バッジ
- turning_up → 青の上矢印バッジ「転換」
- turning_down → オレンジの下矢印バッジ「転換」
- stable → グレーの横矢印バッジ
- volatile → グレーの波線バッジ

### 3-2. 企業詳細 - 指標タブ拡張

`companies/_metrics.html.erb` に成長加速度セクションを追加:
- 「成長加速度」セクション: revenue/operating_income/net_income/eps の加速度を棒グラフで表示
- acceleration_consistency のラベル表示（加速中/減速中/混在）
- 既存の成長率チャートに加速度データを重ねて表示（第2軸）

### 3-3. Chart.js データ拡張

`Company::DashboardSummary` に新しいチャートタイプを追加:
- `growth_acceleration`: 加速度の時系列バーチャート
- 既存の `growth_rates` チャートに加速度のlineデータセットを追加

### 3-4. 検索フィルタ拡張

`ScreeningPreset::ConditionExecutor` に新しい条件タイプを追加:
- `trend_filter`: トレンドラベルによるフィルタリング（data_json内のtrend_*フィールド）
  - 例: `{ type: "trend_filter", field: "trend_revenue", value: "turning_up" }`
- `acceleration_range`: 加速度値の範囲フィルタ（data_json_range で対応可能）

フィルタビルダーUI（`filter_builder_controller.js`）に:
- 条件タイプセレクターに「トレンド分類」を追加
- トレンドフィールド選択（revenue, operating_income, roe等）
- トレンドラベル選択（ドロップダウン: improving, turning_up等）

### 3-5. CSS拡張

`components/badges.css` にトレンドバッジスタイルを追加:
- `.badge-trend-improving`, `.badge-trend-deteriorating`, `.badge-trend-turning-up` 等

---

## テスト

### モデルテスト

- `FinancialMetric.get_growth_acceleration_metrics`:
  - 前期YoY=10%, 当期YoY=15% のとき acceleration=+5.0 であること
  - 前期YoY=15%, 当期YoY=10% のとき acceleration=-5.0 であること
  - 前期または当期のYoYがnilの場合にnilを返すこと
- `FinancialMetric.get_acceleration_consistency`:
  - 3期連続で加速の場合に "accelerating" を返すこと
  - 3期連続で減速の場合に "decelerating" を返すこと
  - 期数が不足する場合にnilを返すこと
- `FinancialMetric.classify_trend`:
  - 3期連続改善で "improving" を返すこと
  - 悪化から改善に転じた場合に "turning_up" を返すこと
  - データが2期分しかない場合にnilを返すこと
  - 変化率が閾値内の場合に "stable" を返すこと

### ヘルパーテスト

- DashboardHelper にトレンドバッジ生成メソッドのテストを追加

---

## ファイル構成

### 変更ファイル

| ファイル | 変更内容 |
|---------|---------|
| `app/models/financial_metric.rb` | data_jsonスキーマ拡張、classify_trend / get_growth_acceleration_metrics / get_acceleration_consistency メソッド追加 |
| `app/jobs/calculate_financial_metrics_job.rb` | 加速度算出・トレンド分類の呼び出し追加 |
| `app/models/screening_preset/condition_executor.rb` | trend_filter 条件タイプ追加 |
| `app/models/company/dashboard_summary.rb` | growth_acceleration チャートデータ追加 |
| `app/helpers/dashboard_helper.rb` | トレンドバッジ生成メソッド追加 |
| `app/views/dashboard/companies/_summary_cards.html.erb` | トレンドバッジ表示追加 |
| `app/views/dashboard/companies/_metrics.html.erb` | 成長加速度セクション追加 |
| `app/javascript/controllers/filter_builder_controller.js` | トレンド分類条件の追加 |
| `app/assets/stylesheets/components/badges.css` | トレンドバッジスタイル追加 |

---

## 実装順序

1. FinancialMetric にクラスメソッド追加（get_growth_acceleration_metrics, get_acceleration_consistency, classify_trend）
2. テスト作成・実行
3. data_json スキーマ拡張
4. CalculateFinancialMetricsJob への組み込み
5. DashboardSummary にチャートデータ追加
6. ダッシュボードビュー更新（サマリーカード・指標タブ）
7. CSS追加
8. ConditionExecutor にtrend_filter追加
9. フィルタビルダーUI更新
10. 全テスト実行
