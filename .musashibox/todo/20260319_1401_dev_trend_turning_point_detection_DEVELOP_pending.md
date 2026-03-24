# DEVELOP: トレンド転換検出・フラグ付け機能の実装

## 概要

企業の財務指標の時系列データにおいて「トレンドの転換点」を自動的に検出し、記録する機能を実装する。これにより、「今まさにトレンドが転換しつつある企業」のスクリーニングや、「業績が飛躍し始める直前のパターン分析」が可能になる。

## 前提条件

- `CalculateFinancialMetricsJob` による `FinancialMetric` の算出が完了していること
- `CalculateSectorMetricsJob` による `SectorMetric` の算出が完了していること（バリュエーション変化検出に必要）

## 関連TODO

- `20260320_2000_dev_financial_event_detection` — より汎用的なイベント検出。本機能はトレンド転換に特化した独立実装であり、将来的に汎用イベントテーブルとの統合を検討可能
- `20260320_1602_dev_metric_trend_classification` — トレンドの方向分類。本機能は転換の「瞬間」を検出する点で異なる
- `20260320_2001_dev_growth_acceleration_metrics` — 成長加速度。本機能の「売上成長率加速」検出で利用可能だが、依存はしない

---

## 1. データモデル設計

### 1-1. データ保持方式の検討結果

3つの方式を検討した結果、**専用テーブル `trend_turning_points` を採用する**。

#### 方式A: financial_metrics.data_json 内にフラグ格納

- 長所: 新テーブル不要、FinancialMetric と一体管理
- 短所: 企業横断のスクリーニングが困難（SQLite の JSON クエリは非効率）、data_json が肥大化する
- 判定: **不採用** — スクリーニングが主目的のため、検索性が最重要

#### 方式B: EAV テーブル（company_properties 的な）

- 長所: 柔軟、拡張性が高い
- 短所: イベント的な時系列データとの相性が悪い、kind 管理が煩雑になる
- 判定: **不採用** — 転換点は「ある期に発生したイベント」であり、EAV の「エンティティの属性」とは性質が異なる

#### 方式C: 専用テーブル `trend_turning_points`

- 長所: 明確なスキーマ、効率的なインデックス、スクリーニングクエリが容易、イベントの時系列管理に自然
- 短所: テーブル追加
- 判定: **採用** — スクリーニングのための検索性、パターン分析のための構造化が最も適している

### 1-2. テーブル定義: `trend_turning_points`

```ruby
create_table :trend_turning_points do |t|
  t.references :company, null: false, foreign_key: true
  t.references :financial_metric, null: false, foreign_key: true
  t.date :fiscal_year_end, null: false
  t.integer :scope, default: 0, null: false          # consolidated / non_consolidated
  t.integer :period_type, null: false                 # annual / q1 / q2 / q3
  t.integer :pattern_type, null: false                # enum: 検出パターン種別
  t.integer :significance, default: 1, null: false    # enum: 注目度
  t.json :data_json                                   # 検出詳細データ

  t.timestamps
end

add_index :trend_turning_points, [:company_id, :fiscal_year_end], name: "idx_ttp_company_fy"
add_index :trend_turning_points, [:pattern_type, :fiscal_year_end], name: "idx_ttp_pattern_fy"
add_index :trend_turning_points, [:significance, :fiscal_year_end], name: "idx_ttp_significance_fy"
add_index :trend_turning_points, [:company_id, :pattern_type, :fiscal_year_end, :scope, :period_type], unique: true, name: "idx_ttp_unique"
```

### 1-3. モデル定義: `TrendTurningPoint`

```ruby
class TrendTurningPoint < ApplicationRecord
  include JsonAttribute

  belongs_to :company
  belongs_to :financial_metric

  enum :scope, {
    consolidated: 0,
    non_consolidated: 1,
  }

  enum :period_type, {
    annual: 0,
    q1: 1,
    q2: 2,
    q3: 3,
  }

  # 検出パターン種別
  enum :pattern_type, {
    growth_resumption: 1,          # 増収増益の開始
    margin_bottom_reversal: 2,     # 利益率の底打ち反転
    free_cf_turnaround: 3,         # フリーCF黒字転換
    roe_reversal: 4,               # ROE反転上昇
    revenue_growth_acceleration: 5, # 売上成長率の加速
    valuation_shift: 6,            # バリュエーション急変
  }

  # 注目度（検出条件の強さ）
  enum :significance, {
    low: 0,       # 単純な転換（1期の変化）
    medium: 1,    # 複数期のパターンに基づく転換
    high: 2,      # 長期トレンドの転換（前期まで複数期悪化していた場合など）
  }

  define_json_attributes :data_json, schema: {
    # 共通
    description: { type: :string },           # 検出パターンの説明文
    # growth_resumption 用
    prior_decline_periods: { type: :integer }, # 転換前の減収/減益期数
    current_revenue_yoy: { type: :decimal },
    current_net_income_yoy: { type: :decimal },
    # margin_bottom_reversal 用
    prior_decline_count: { type: :integer },   # 低下が続いた期数
    previous_margin: { type: :decimal },
    current_margin: { type: :decimal },
    margin_delta: { type: :decimal },
    # free_cf_turnaround 用
    previous_free_cf: { type: :integer },
    current_free_cf: { type: :integer },
    # roe_reversal 用
    previous_roe: { type: :decimal },
    current_roe: { type: :decimal },
    roe_delta: { type: :decimal },
    # revenue_growth_acceleration 用
    previous_revenue_yoy: { type: :decimal },
    acceleration: { type: :decimal },          # current_yoy - previous_yoy
    # valuation_shift 用
    metric_name: { type: :string },            # "per" or "pbr"
    current_value: { type: :decimal },
    sector_median: { type: :decimal },
    deviation_ratio: { type: :decimal },       # (current - median) / median
  }
end
```

---

## 2. 検出パターン定義と優先順位

### 優先度A（初回実装）

#### P1: growth_resumption — 増収増益の開始

**定義**: `consecutive_revenue_growth` が 0 → 1 に転じた期

**検出ロジック**:
```
条件:
  current_metric.consecutive_revenue_growth == 1
  AND previous_metric.consecutive_revenue_growth == 0
```

**注目度判定**:
- `high`: 前期まで2期以上連続で `revenue_yoy < 0` だった場合（長期減収からの回復）
- `medium`: 前期の `revenue_yoy <= 0` だった場合（減収からの回復）
- `low`: 上記に該当しないがカウントが0→1に転じた場合

**data_json に格納するデータ**:
- `prior_decline_periods`: 転換前に `revenue_yoy < 0` が連続していた期数（遡って調査）
- `current_revenue_yoy`: 当期の売上成長率
- `current_net_income_yoy`: 当期の純利益成長率（増収増益の両立確認用）
- `description`: "N期連続減収からの増収転換" のような説明文

**実装メソッド**: `TrendTurningPoint.detect_growth_resumption(current_metric, previous_metric, history)`
- `history`: 過去の FinancialMetric 配列（fiscal_year_end 降順、3〜5期分）

#### P2: free_cf_turnaround — フリーCF黒字転換

**定義**: `free_cf_positive` が false → true に転じた期

**検出ロジック**:
```
条件:
  current_metric.free_cf_positive == true
  AND previous_metric.free_cf_positive == false
  AND previous_metric.free_cf_positive IS NOT NULL
```

**注目度判定**:
- `high`: 前期まで2期以上 `free_cf_positive == false` が継続
- `medium`: 前期のみ `free_cf_positive == false`
- `low`: 条件に合致するがデータ不足

**data_json に格納するデータ**:
- `previous_free_cf`: 前期のフリーCF額
- `current_free_cf`: 当期のフリーCF額
- `description`: "フリーキャッシュフロー黒字転換"

**実装メソッド**: `TrendTurningPoint.detect_free_cf_turnaround(current_metric, previous_metric, history)`

#### P3: margin_bottom_reversal — 利益率の底打ち反転

**定義**: `operating_margin` が2期以上連続低下した後に反転上昇した期

**検出ロジック**:
```
条件（history は fiscal_year_end 降順で3期以上必要）:
  history[0].operating_margin > history[1].operating_margin  # 当期 > 前期（反転）
  AND history[1].operating_margin < history[2].operating_margin  # 前期 < 前々期（低下中だった）
```

**注目度判定**:
- `high`: 3期以上連続低下からの反転
- `medium`: 2期連続低下からの反転
- `low`: 上記に該当しない（例: operating_margin が nil の期を含む場合のベストエフォート検出）

**data_json に格納するデータ**:
- `prior_decline_count`: 連続低下していた期数
- `previous_margin`: 前期の operating_margin
- `current_margin`: 当期の operating_margin
- `margin_delta`: 当期 - 前期
- `description`: "N期連続の営業利益率低下からの底打ち反転"

**実装メソッド**: `TrendTurningPoint.detect_margin_bottom_reversal(history)`
- `history`: 過去3〜5期分の FinancialMetric 配列（fiscal_year_end 降順）

### 優先度B（初回実装、データ可用性に依存）

#### P4: roe_reversal — ROE反転上昇

**定義**: ROE が2期以上連続低下した後に反転上昇した期

**検出ロジック**: margin_bottom_reversal と同様のロジックだが、対象が `roe`

```
条件（3期以上のhistory）:
  history[0].roe > history[1].roe
  AND history[1].roe < history[2].roe
```

**注目度判定**:
- `high`: 3期以上連続低下からの反転
- `medium`: 2期連続低下からの反転

**data_json**: `previous_roe`, `current_roe`, `roe_delta`, `prior_decline_count`, `description`

**実装メソッド**: `TrendTurningPoint.detect_roe_reversal(history)`

#### P5: revenue_growth_acceleration — 売上成長率の加速

**定義**: `revenue_yoy > 0` かつ当期の `revenue_yoy` が前期の `revenue_yoy` を上回る

**検出ロジック**:
```
条件:
  current_metric.revenue_yoy > 0
  AND previous_metric.revenue_yoy IS NOT NULL
  AND current_metric.revenue_yoy > previous_metric.revenue_yoy
```

**注目度判定**:
- `high`: 加速幅が10ポイント以上（例: 5% → 15%）かつ2期連続加速
- `medium`: 加速幅が5ポイント以上
- `low`: 上記以外の加速

**data_json**: `previous_revenue_yoy`, `current_revenue_yoy`, `acceleration` (差分), `description`

**実装メソッド**: `TrendTurningPoint.detect_revenue_growth_acceleration(current_metric, previous_metric, history)`

### 優先度C（SectorMetric 依存）

#### P6: valuation_shift — バリュエーション急変

**定義**: PER または PBR がセクター中央値対比で大幅に変化した期

**検出ロジック**:
```
条件（PER の場合）:
  current_per = current_metric.per
  sector_median_per = sector_metric.data_json["per"]["median"]

  deviation_ratio = (current_per - sector_median_per) / sector_median_per

  # 偏差率が前期と比較して大幅に変化
  前期の deviation_ratio と当期の deviation_ratio の差が 0.3（30ポイント）以上
```

**注目度判定**:
- `high`: 偏差変化率が50ポイント以上
- `medium`: 偏差変化率が30ポイント以上

**data_json**: `metric_name`, `current_value`, `sector_median`, `deviation_ratio`, `description`

**実装メソッド**: `TrendTurningPoint.detect_valuation_shift(current_metric, previous_metric, sector_metric_map)`
- `sector_metric_map`: `SectorMetric.load_latest_map` の結果

---

## 3. 検出エンジンの実装

### 3-1. TrendTurningPoint モデルへの検出メソッド

各パターンの検出メソッドは `TrendTurningPoint` のクラスメソッドとして実装する。既存の `FinancialMetric` の設計パターン（ステートレスなクラスメソッドで計算）に倣う。

```ruby
class TrendTurningPoint < ApplicationRecord
  # ...（enum, associations は前述の通り）

  # P1: 増収増益の開始を検出
  # @param current_metric [FinancialMetric]
  # @param previous_metric [FinancialMetric, nil]
  # @param history [Array<FinancialMetric>] fiscal_year_end 降順、3-5期分
  # @return [Hash, nil] 検出された場合は属性Hash、未検出はnil
  def self.detect_growth_resumption(current_metric, previous_metric, history)
    # ...
  end

  # P2: フリーCF黒字転換を検出
  def self.detect_free_cf_turnaround(current_metric, previous_metric, history)
    # ...
  end

  # P3: 利益率の底打ち反転を検出
  # @param history [Array<FinancialMetric>] fiscal_year_end 降順、最低3期分
  def self.detect_margin_bottom_reversal(history)
    # ...
  end

  # P4: ROE反転上昇を検出
  def self.detect_roe_reversal(history)
    # ...
  end

  # P5: 売上成長率の加速を検出
  def self.detect_revenue_growth_acceleration(current_metric, previous_metric, history)
    # ...
  end

  # P6: バリュエーション急変を検出
  def self.detect_valuation_shift(current_metric, previous_metric, sector_metric_map)
    # ...
  end

  # 全パターンを検出し、結果を配列で返す
  # @return [Array<Hash>] 検出されたパターンのHash配列
  def self.detect_all(current_metric, previous_metric, history, sector_metric_map: nil)
    results = []
    results << detect_growth_resumption(current_metric, previous_metric, history)
    results << detect_free_cf_turnaround(current_metric, previous_metric, history)
    results << detect_margin_bottom_reversal(history)
    results << detect_roe_reversal(history)
    results << detect_revenue_growth_acceleration(current_metric, previous_metric, history)
    results << detect_valuation_shift(current_metric, previous_metric, sector_metric_map) if sector_metric_map
    results.compact
  end
end
```

各検出メソッドは検出した場合に以下のような Hash を返す:

```ruby
{
  pattern_type: :growth_resumption,
  significance: :high,
  data_json: {
    "prior_decline_periods" => 3,
    "current_revenue_yoy" => 0.15,
    "current_net_income_yoy" => 0.08,
    "description" => "3期連続減収からの増収転換",
  },
}
```

### 3-2. ヘルパーメソッド

```ruby
class TrendTurningPoint < ApplicationRecord
  # history 配列から、あるメトリックの連続低下期数を算出
  # @param history [Array<FinancialMetric>] fiscal_year_end 降順
  # @param attribute [Symbol] 対象の属性名
  # @return [Integer] 連続低下期数（0 = 低下なし）
  def self.get_consecutive_decline_count(history, attribute)
    # history[1] から遡り、history[i].send(attribute) < history[i+1].send(attribute) が
    # 続く限りカウントする
  end

  # 注目度の判定（margin_bottom_reversal, roe_reversal 共通）
  def self.get_reversal_significance(decline_count)
    if decline_count >= 3
      :high
    elsif decline_count >= 2
      :medium
    else
      :low
    end
  end
end
```

---

## 4. ジョブ設計: DetectTrendTurningPointsJob

`CalculateFinancialMetricsJob` とは **別ジョブ** として実装する。

### 理由

- `CalculateFinancialMetricsJob` は1つの FinancialValue に対して前期のデータのみを参照して計算するが、トレンド転換の検出には3〜5期分の履歴が必要
- 責務の分離: 指標算出と転換点検出は異なる関心事
- パイプライン上の依存: 転換点検出は全指標の算出完了後に実行すべき（特にバリュエーション系は SectorMetric も必要）

### ジョブ定義

```ruby
class DetectTrendTurningPointsJob < ApplicationJob
  HISTORY_DEPTH = 5  # 遡る期数

  # @param recalculate [Boolean] true の場合、既存の検出結果を削除して全件再検出
  # @param company_id [Integer, nil] 特定企業のみ対象とする場合
  # @param fiscal_year_end [Date, nil] 特定の決算期のみ対象とする場合
  def perform(recalculate: false, company_id: nil, fiscal_year_end: nil)
    # ...
  end

  private

  # 対象の FinancialMetric を取得
  # 連結・通期のみを対象（スクリーニング用途の主軸）
  def build_target_scope(recalculate:, company_id:, fiscal_year_end:)
    scope = FinancialMetric.where(scope: :consolidated, period_type: :annual)
    scope = scope.where(company_id: company_id) if company_id
    scope = scope.where(fiscal_year_end: fiscal_year_end) if fiscal_year_end

    unless recalculate
      # まだ検出が実行されていない FinancialMetric を対象
      # (updated_at が TrendTurningPoint の最終更新より新しいもの)
      scope = scope.where(
        "financial_metrics.updated_at > ? OR NOT EXISTS (
          SELECT 1 FROM trend_turning_points ttp
          WHERE ttp.financial_metric_id = financial_metrics.id
        )", last_detection_time
      )
    end

    scope
  end

  # 指定された FinancialMetric の企業に対して履歴を取得し、転換点を検出
  def detect_for_metric(metric)
    history = load_history(metric.company_id, metric.fiscal_year_end, metric.scope, metric.period_type)
    return if history.size < 2

    current_metric = history[0]
    previous_metric = history[1]

    sector_metric_map = load_sector_metric_map(metric.company)

    results = TrendTurningPoint.detect_all(
      current_metric, previous_metric, history,
      sector_metric_map: sector_metric_map,
    )

    save_results(metric, results)
  end

  # 履歴を取得（fiscal_year_end 降順）
  def load_history(company_id, fiscal_year_end, scope_val, period_type_val)
    FinancialMetric
      .where(company_id: company_id, scope: scope_val, period_type: period_type_val)
      .where("fiscal_year_end <= ?", fiscal_year_end)
      .order(fiscal_year_end: :desc)
      .limit(HISTORY_DEPTH)
      .to_a
  end

  # SectorMetric のマップを取得
  def load_sector_metric_map(company)
    return nil unless company.sector_33_code.present?
    @sector_map_cache ||= SectorMetric.load_latest_map(:sector_33)
    @sector_map_cache
  end

  # 検出結果を保存（同一 metric + pattern_type の重複は更新）
  def save_results(metric, results)
    results.each do |result|
      ttp = TrendTurningPoint.find_or_initialize_by(
        company_id: metric.company_id,
        financial_metric_id: metric.id,
        pattern_type: result[:pattern_type],
        fiscal_year_end: metric.fiscal_year_end,
        scope: metric.scope,
        period_type: metric.period_type,
      )
      ttp.assign_attributes(
        significance: result[:significance],
        data_json: result[:data_json],
      )
      ttp.save! if ttp.new_record? || ttp.changed?
    end
  end
end
```

---

## 5. スクリーニングクエリ: Company::TrendTurningPointQuery

### 目的

検出されたトレンド転換点に基づいて企業をスクリーニングする。

### インターフェース

```ruby
class Company::TrendTurningPointQuery
  # @param pattern_type [Symbol, nil] 特定のパターンに限定（nil で全パターン）
  # @param significance [Symbol, nil] 最低注目度（nil で制限なし）
  # @param since [Date, nil] この日以降の fiscal_year_end に限定
  # @param sector_33_code [String, nil] セクターで絞り込み
  # @param limit [Integer, nil] 最大件数
  def initialize(pattern_type: nil, significance: nil, since: nil, sector_33_code: nil, limit: nil)
    # ...
  end

  # @return [Array<Hash>] 検出結果の配列
  #   各要素: { company:, turning_point:, financial_metric: }
  def execute
    # ...
  end
end
```

### ユースケース別の利用例

```ruby
# 直近1年以内にフリーCF黒字転換した企業
Company::TrendTurningPointQuery.new(
  pattern_type: :free_cf_turnaround,
  since: 1.year.ago.to_date,
).execute

# 注目度 high の増収転換企業（長期減収からの回復）
Company::TrendTurningPointQuery.new(
  pattern_type: :growth_resumption,
  significance: :high,
  since: 2.years.ago.to_date,
).execute

# 直近で利益率が底打ち反転した企業（全パターン、注目度medium以上）
Company::TrendTurningPointQuery.new(
  pattern_type: :margin_bottom_reversal,
  significance: :medium,
  since: 1.year.ago.to_date,
).execute
```

---

## 6. 実装手順

### Step 1: マイグレーション・モデル

1. `trend_turning_points` テーブルのマイグレーション作成・適用
2. `TrendTurningPoint` モデル作成（enum, associations, JsonAttribute）
3. `Company` モデルに `has_many :trend_turning_points` を追加

### Step 2: 検出ロジック（優先度A: P1〜P3）

4. `TrendTurningPoint.detect_growth_resumption` 実装
5. `TrendTurningPoint.detect_free_cf_turnaround` 実装
6. `TrendTurningPoint.detect_margin_bottom_reversal` 実装
7. ヘルパーメソッド（`get_consecutive_decline_count`, `get_reversal_significance`）実装
8. 各検出メソッドのテスト作成

### Step 3: 検出ロジック（優先度B: P4〜P5）

9. `TrendTurningPoint.detect_roe_reversal` 実装
10. `TrendTurningPoint.detect_revenue_growth_acceleration` 実装
11. 各検出メソッドのテスト作成

### Step 4: 検出ロジック（優先度C: P6）

12. `TrendTurningPoint.detect_valuation_shift` 実装（SectorMetric 参照）
13. テスト作成

### Step 5: 統合検出メソッド

14. `TrendTurningPoint.detect_all` 実装
15. テスト作成

### Step 6: ジョブ

16. `DetectTrendTurningPointsJob` 実装
17. 履歴取得・結果保存ロジックの実装

### Step 7: スクリーニングクエリ

18. `Company::TrendTurningPointQuery` 実装
19. テスト作成

---

## 7. テスト方針

### TrendTurningPoint モデルテスト (`spec/models/trend_turning_point_spec.rb`)

各検出メソッドに対して、FinancialMetric のインスタンスをビルドしてテストする（DB不要）。

```ruby
describe TrendTurningPoint do
  describe ".detect_growth_resumption" do
    context "consecutive_revenue_growth が 0 → 1 に転じた場合" do
      it "growth_resumption を返す"
    end

    context "前期まで3期連続減収だった場合" do
      it "significance: :high で返す"
    end

    context "consecutive_revenue_growth が 1 → 2 の場合（転換ではない）" do
      it "nil を返す"
    end
  end

  describe ".detect_free_cf_turnaround" do
    context "free_cf_positive が false → true に転じた場合" do
      it "free_cf_turnaround を返す"
    end

    context "free_cf_positive が true → true の場合" do
      it "nil を返す"
    end
  end

  describe ".detect_margin_bottom_reversal" do
    context "operating_margin が2期連続低下後に反転した場合" do
      it "margin_bottom_reversal を返す"
    end

    context "history が2期しかない場合" do
      it "nil を返す"
    end
  end

  # P4〜P6 も同様のパターンでテスト

  describe ".detect_all" do
    it "複数パターンが同時検出された場合、すべてを返す"
    it "何も検出されない場合、空配列を返す"
  end

  describe ".get_consecutive_decline_count" do
    it "連続低下期数を正しくカウントする"
  end
end
```

### ジョブはモデルメソッドのテストでカバーし、ジョブ自体の実行テストは記述しない（テスティング規約に従う）。

### Company::TrendTurningPointQuery テスト (`spec/models/company/trend_turning_point_query_spec.rb`)

DB読み書きが必要なため、最小限のレコードを用意して結果を検証する。

---

## 8. ファイル一覧

### 新規作成

| ファイル | 内容 |
|---|---|
| `db/migrate/YYYYMMDDHHMMSS_create_trend_turning_points.rb` | マイグレーション |
| `app/models/trend_turning_point.rb` | モデル（検出ロジック含む） |
| `app/models/company/trend_turning_point_query.rb` | スクリーニングクエリ |
| `app/jobs/detect_trend_turning_points_job.rb` | 検出ジョブ |
| `spec/models/trend_turning_point_spec.rb` | モデルテスト |
| `spec/models/company/trend_turning_point_query_spec.rb` | クエリテスト |

### 変更

| ファイル | 変更内容 |
|---|---|
| `app/models/company.rb` | `has_many :trend_turning_points` 追加 |
