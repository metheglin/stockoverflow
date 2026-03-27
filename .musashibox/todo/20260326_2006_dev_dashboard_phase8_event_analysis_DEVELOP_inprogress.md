# DEVELOP: ダッシュボード Phase 8 - イベント検出・転換点分析・パーセンタイル

## 概要

財務イベントの自動検出、トレンド転換点の検出、パーセンタイルランキングの3機能を実装し、ダッシュボードの企業詳細画面にイベントフィード・転換点セクション・改善されたセクターポジション表示を追加する。

## 背景

Phase 6でデータエンリッチメント（トレンド分類・加速度）、Phase 7で高度なスクリーニングを実装した後、次のステップとして「企業に何が起きたか」を可視化する機能が重要になる。特に:

- プロジェクトのユースケース「業績が飛躍し始める直前の変化を捉える」に直結
- 企業詳細ページの情報密度を大幅に向上
- スクリーニング条件として「転換点が検出された企業」を使えるようになる

## 前提・依存

- Phase 6（トレンド分類・加速度）が完了していること（推奨・一部利用）
- CalculateFinancialMetricsJob / CalculateSectorMetricsJob が稼働していること

## 参照する既存TODO

- `20260320_2000_dev_financial_event_detection_DEVELOP_pending.md` — 財務イベント検出のバックエンド仕様
- `20260319_1401_dev_trend_turning_point_detection_DEVELOP_pending.md` — 転換点検出のバックエンド仕様
- `20260320_1601_dev_metric_percentile_ranking_DEVELOP_pending.md` — パーセンタイルランキングの仕様

---

## Part 1: 財務イベント検出

### 1-1. マイグレーション

```ruby
create_table :financial_events do |t|
  t.references :company, null: false, foreign_key: true
  t.references :financial_metric, null: false, foreign_key: true
  t.integer :event_type, null: false
  t.integer :severity, null: false, default: 0
  t.date :fiscal_year_end, null: false
  t.json :data_json
  t.timestamps
end

add_index :financial_events, [:company_id, :fiscal_year_end]
add_index :financial_events, [:event_type, :created_at]
add_index :financial_events, [:company_id, :event_type, :fiscal_year_end], unique: true, name: "idx_fin_events_unique"
```

### 1-2. FinancialEvent モデル

参照TODO `dev_financial_event_detection` の仕様に準拠。

enum: event_type (streak_started, streak_broken, streak_milestone, fcf_turned_positive, fcf_turned_negative, margin_expansion, margin_contraction, roe_crossed_threshold, extreme_growth, extreme_decline, growth_acceleration, growth_deceleration)

enum: severity (info, notable, critical)

### 1-3. 検出メソッド

`FinancialEvent` にクラスメソッドとして実装:

```ruby
# @param current_metric [FinancialMetric]
# @param previous_metric [FinancialMetric, nil]
# @return [Array<Hash>] 検出されたイベントの属性Hash配列
def self.detect_events(current_metric, previous_metric)
end
```

### 1-4. CalculateFinancialMetricsJob への組み込み

メトリクス算出後にイベント検出を実行し、FinancialEventを保存。冪等性: company_id + event_type + fiscal_year_end のユニーク制約で重複防止。

---

## Part 2: トレンド転換点検出

### 2-1. マイグレーション

参照TODO `dev_trend_turning_point_detection` の仕様に準拠。

```ruby
create_table :trend_turning_points do |t|
  t.references :company, null: false, foreign_key: true
  t.references :financial_metric, null: false, foreign_key: true
  t.date :fiscal_year_end, null: false
  t.integer :scope, default: 0, null: false
  t.integer :period_type, null: false
  t.integer :pattern_type, null: false
  t.integer :significance, default: 1, null: false
  t.json :data_json
  t.timestamps
end

add_index :trend_turning_points, [:company_id, :fiscal_year_end], name: "idx_ttp_company_fy"
add_index :trend_turning_points, [:pattern_type, :fiscal_year_end], name: "idx_ttp_pattern_fy"
add_index :trend_turning_points, [:company_id, :pattern_type, :fiscal_year_end, :scope, :period_type], unique: true, name: "idx_ttp_unique"
```

### 2-2. TrendTurningPoint モデル

参照TODOの仕様に準拠。6つの検出パターン:
- growth_resumption（増収増益の開始）
- margin_bottom_reversal（利益率の底打ち反転）
- free_cf_turnaround（フリーCF黒字転換）
- roe_reversal（ROE反転上昇）
- revenue_growth_acceleration（売上成長率の加速）
- valuation_shift（バリュエーション急変）

### 2-3. DetectTrendTurningPointsJob

CalculateFinancialMetricsJob とは別ジョブとして実装。過去3-5期分の履歴を取得して転換点を検出。

---

## Part 3: パーセンタイルランキング

### 3-1. 算出タイミング

CalculateSectorMetricsJob の後処理として、各企業のパーセンタイルランキングを算出。

### 3-2. data_json スキーマ拡張（FinancialMetric）

```ruby
# セクター内パーセンタイル
sector_percentile_roe: { type: :decimal },
sector_percentile_roa: { type: :decimal },
sector_percentile_operating_margin: { type: :decimal },
sector_percentile_revenue_yoy: { type: :decimal },
sector_percentile_per: { type: :decimal },
sector_percentile_pbr: { type: :decimal },
# 市場全体パーセンタイル
market_percentile_roe: { type: :decimal },
market_percentile_operating_margin: { type: :decimal },
```

### 3-3. 算出メソッド

```ruby
# セクター内での企業のパーセンタイル順位を算出
# @param company_value [Numeric] 企業の指標値
# @param sector_values [Array<Numeric>] セクター内全企業の値
# @return [Float] 0.0〜1.0のパーセンタイル値
def self.get_percentile(company_value, sector_values)
  return nil if sector_values.empty? || company_value.nil?
  sorted = sector_values.compact.sort
  rank = sorted.count { |v| v < company_value }
  rank.to_f / sorted.size
end
```

---

## Part 4: ダッシュボードUI統合

### 4-1. 企業詳細 - イベントフィードセクション

`companies/show.html.erb` の既存タブの上部（サマリーカードの下）に「最近のイベント」セクションを追加:

```erb
<div class="events-feed">
  <h3>最近のイベント</h3>
  <% @events.each do |event| %>
    <div class="event-item event-<%= event.severity %>">
      <span class="event-date"><%= event.fiscal_year_end %></span>
      <span class="event-badge badge-<%= event.severity %>"><%= event.severity %></span>
      <span class="event-description"><%= event.data_json["description"] || event.event_type.humanize %></span>
    </div>
  <% end %>
</div>
```

- severity: critical → 赤背景、notable → 黄背景、info → グレー背景
- 最新の10件を表示
- 「もっと見る」で全件展開

### 4-2. 企業詳細 - 転換点タイムライン

指標タブ（`_metrics.html.erb`）に「転換点」セクションを追加:

- 転換点を時系列で表示（タイムラインUI）
- 各転換点にパターン名、注目度、説明文を表示
- significance: high は目立つアイコン付き

### 4-3. セクターポジション改善

既存の `_sector_position.html.erb` を改善:

- 現在はquartile（4分位）による近似表示
- パーセンタイル値が利用可能な場合、正確なパーセンタイル位置を表示
- 「セクター内上位XX%」のラベル表示

### 4-4. コントローラー変更

`Dashboard::CompaniesController#show`:
- `@events = FinancialEvent.where(company_id: @company.id).order(fiscal_year_end: :desc).limit(10)` を追加

`Dashboard::CompaniesController#metrics`:
- `@turning_points = TrendTurningPoint.where(company_id: @company.id).order(fiscal_year_end: :desc)` を追加

### 4-5. 検索での活用

ConditionExecutorに転換点スクリーニング条件を追加:

```json
{
  "type": "turning_point",
  "pattern_type": "growth_resumption",
  "significance": "high",
  "since_months": 12
}
```

ConditionExecutorのポストフィルタとして、TrendTurningPointテーブルをJOINして条件適用。

### 4-6. CSS

新規CSS:
- `components/events.css` - イベントフィードのスタイル（severity別の配色、タイムラインUI）

---

## テスト

### FinancialEvent テスト

`spec/models/financial_event_spec.rb`:
- `FinancialEvent.detect_events`: 連続増収増益が0→1で streak_started が検出されること
- 3期以上のストリーク中断で streak_broken が検出されること
- FCFの正負転換イベントが正しく検出されること
- 前期データがない場合にエラーにならないこと

### TrendTurningPoint テスト

`spec/models/trend_turning_point_spec.rb`:
- 各パターン（growth_resumption, free_cf_turnaround, margin_bottom_reversal等）の検出テスト
- significance の判定テスト
- detect_all が複数パターン同時検出を返すこと
- get_consecutive_decline_count のカウントテスト

### パーセンタイル テスト

- get_percentile の算出テスト（正常ケース、空配列、1社のみ）

---

## ファイル構成

### 新規作成

| ファイル | 内容 |
|---------|------|
| `db/migrate/xxx_create_financial_events.rb` | financial_events テーブル |
| `db/migrate/xxx_create_trend_turning_points.rb` | trend_turning_points テーブル |
| `app/models/financial_event.rb` | イベントモデル（検出ロジック含む） |
| `app/models/trend_turning_point.rb` | 転換点モデル（検出ロジック含む） |
| `app/jobs/detect_trend_turning_points_job.rb` | 転換点検出ジョブ |
| `app/views/dashboard/companies/_events_feed.html.erb` | イベントフィードパーシャル |
| `app/views/dashboard/companies/_turning_points.html.erb` | 転換点タイムラインパーシャル |
| `app/assets/stylesheets/components/events.css` | イベント表示スタイル |
| `spec/models/financial_event_spec.rb` | イベントテスト |
| `spec/models/trend_turning_point_spec.rb` | 転換点テスト |

### 変更ファイル

| ファイル | 変更内容 |
|---------|---------|
| `app/models/company.rb` | `has_many :financial_events`, `has_many :trend_turning_points` 追加 |
| `app/models/financial_metric.rb` | パーセンタイルdata_jsonスキーマ拡張 |
| `app/jobs/calculate_financial_metrics_job.rb` | イベント検出呼び出し追加 |
| `app/controllers/dashboard/companies_controller.rb` | @events, @turning_points の取得追加 |
| `app/views/dashboard/companies/show.html.erb` | イベントフィード表示追加 |
| `app/views/dashboard/companies/_metrics.html.erb` | 転換点セクション追加 |
| `app/views/dashboard/companies/_sector_position.html.erb` | パーセンタイル表示改善 |
| `app/models/screening_preset/condition_executor.rb` | turning_point条件タイプ追加 |

---

## 実装順序

### Step 1: 財務イベント検出
1. マイグレーション作成・適用
2. FinancialEvent モデル作成（detect_events メソッド含む）
3. テスト作成・実行
4. CalculateFinancialMetricsJob への組み込み

### Step 2: トレンド転換点検出
5. マイグレーション作成・適用
6. TrendTurningPoint モデル作成（6パターンの検出メソッド）
7. テスト作成・実行
8. DetectTrendTurningPointsJob 実装

### Step 3: パーセンタイルランキング
9. FinancialMetric data_json スキーマ拡張
10. パーセンタイル算出メソッド実装
11. CalculateSectorMetricsJob 後処理に組み込み
12. テスト作成・実行

### Step 4: ダッシュボードUI統合
13. コントローラー更新（イベント・転換点の取得）
14. イベントフィードパーシャル作成
15. 転換点タイムラインパーシャル作成
16. セクターポジション改善
17. CSS作成
18. ConditionExecutor に turning_point 条件追加

### Step 5: 最終検証
19. 全テスト実行
20. ダッシュボード動作確認
