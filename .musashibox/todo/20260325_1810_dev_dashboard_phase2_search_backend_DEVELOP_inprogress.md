# DEVELOP: WEBダッシュボード Phase 2 - 検索ダッシュボード バックエンド

## 概要

検索ダッシュボードのバックエンド（コントローラー、スクリーニングプリセットモデル、動的フィルタ条件のJSON仕様）を実装する。

## 元計画

- `todo/20260325_1810_plan_web_dashboard_PLAN_done.md`

## 前提・依存

- Phase 1（基盤構築）が完了していること
- `dev_analysis_query_layer` (20260312_1000) が完了していること（`ScreeningQuery`等が利用可能であること）
  - もし未完了の場合、本フェーズの実装時に必要な `ScreeningQuery` の最小実装を含める

---

## 1. スクリーニングプリセットのDB設計

### 1-1. screening_presets テーブル

検索条件を名前付きで永続化するテーブル。

```ruby
# db/migrate/XXXXXXXX_create_screening_presets.rb
class CreateScreeningPresets < ActiveRecord::Migration[8.1]
  def change
    create_table :screening_presets do |t|
      t.string :name, null: false
      t.text :description
      t.integer :preset_type, null: false, default: 0
      t.json :conditions_json, null: false, default: {}
      t.json :display_json, null: false, default: {}
      t.integer :status, null: false, default: 1
      t.integer :execution_count, null: false, default: 0
      t.datetime :last_executed_at

      t.timestamps
    end

    add_index :screening_presets, :preset_type
    add_index :screening_presets, :status
  end
end
```

### 1-2. ScreeningPreset モデル

```ruby
# app/models/screening_preset.rb
class ScreeningPreset < ApplicationRecord
  include JsonAttribute

  enum :preset_type, {
    builtin: 0,   # ビルトインプリセット
    custom: 1,    # ユーザー定義
  }

  enum :status, {
    disabled: 0,
    enabled: 1,
  }

  define_json_attributes :conditions_json, schema: {
    # 後述のconditions_jsonスキーマ参照
  }

  define_json_attributes :display_json, schema: {
    columns: { type: :array },        # 結果一覧に表示するカラム名のリスト
    sort_by: { type: :string },       # ソートカラム
    sort_order: { type: :string },    # asc / desc
    limit: { type: :integer },        # 表示件数上限
  }
end
```

---

## 2. conditions_json のスキーマ定義

検索条件は以下のJSON構造で保存される。AND/OR の論理演算をサポートする。

### 2-1. 基本構造

```json
{
  "scope_type": "consolidated",
  "period_type": "annual",
  "logic": "and",
  "conditions": [
    {
      "type": "metric_range",
      "field": "roe",
      "min": 0.1,
      "max": null
    },
    {
      "type": "metric_boolean",
      "field": "operating_cf_positive",
      "value": true
    },
    {
      "type": "metric_range",
      "field": "consecutive_revenue_growth",
      "min": 6,
      "max": null
    },
    {
      "type": "company_attribute",
      "field": "sector_33_code",
      "values": ["3050", "3100"]
    },
    {
      "type": "company_attribute",
      "field": "market_code",
      "values": ["111"]
    },
    {
      "type": "metric_top_n",
      "field": "per",
      "direction": "asc",
      "n": 50
    },
    {
      "type": "preset_ref",
      "preset_id": 3
    }
  ]
}
```

### 2-2. 条件タイプ一覧

| type | 説明 | パラメータ |
|------|------|-----------|
| `metric_range` | 数値指標の範囲フィルタ | `field`, `min`, `max`（いずれかまたは両方） |
| `metric_boolean` | Boolean指標のフィルタ | `field`, `value` (true/false) |
| `company_attribute` | 企業属性によるフィルタ | `field`, `values` (配列、ORで結合) |
| `metric_top_n` | 指標の上位/下位N件 | `field`, `direction` (asc/desc), `n` |
| `data_json_range` | data_json内の指標の範囲フィルタ | `field`, `min`, `max` |
| `preset_ref` | 他のプリセットを条件として参照 | `preset_id` |

### 2-3. logic フィールド

- `"and"` : 全条件をANDで結合（デフォルト）
- `"or"` : 全条件をORで結合
- ネスト可能: conditions内にさらに `{"logic": "or", "conditions": [...]}` を配置できる

```json
{
  "scope_type": "consolidated",
  "period_type": "annual",
  "logic": "and",
  "conditions": [
    { "type": "metric_range", "field": "roe", "min": 0.1 },
    {
      "logic": "or",
      "conditions": [
        { "type": "metric_range", "field": "revenue_yoy", "min": 0.2 },
        { "type": "metric_range", "field": "consecutive_revenue_growth", "min": 3 }
      ]
    }
  ]
}
```

### 2-4. フィルタ可能なフィールド一覧

**metric_range / metric_boolean で使用可能:**

固定カラム:
- `revenue_yoy`, `operating_income_yoy`, `ordinary_income_yoy`, `net_income_yoy`, `eps_yoy`
- `roe`, `roa`, `operating_margin`, `ordinary_margin`, `net_margin`
- `free_cf`
- `consecutive_revenue_growth`, `consecutive_profit_growth`
- `operating_cf_positive`, `investing_cf_negative`, `free_cf_positive` (boolean)

**data_json_range で使用可能:**

- `per`, `pbr`, `psr`, `dividend_yield`, `ev_ebitda`
- `current_ratio`, `debt_to_equity`, `net_debt_to_equity`
- `asset_turnover`, `gross_margin`, `sga_ratio`
- `growth_score`, `quality_score`, `value_score`, `composite_score`
- `revenue_cagr_3y`, `revenue_cagr_5y`, `operating_income_cagr_3y`, `operating_income_cagr_5y`
- `net_income_cagr_3y`, `net_income_cagr_5y`, `eps_cagr_3y`, `eps_cagr_5y`
- `payout_ratio`, `dividend_growth_rate`, `consecutive_dividend_growth`

**company_attribute で使用可能:**

- `sector_17_code`, `sector_33_code`, `market_code`, `scale_category`

---

## 3. 条件実行エンジン: ScreeningPreset::ConditionExecutor

検索条件JSONを受け取り、SQLクエリを構築・実行するクラス。

**配置先**: `app/models/screening_preset/condition_executor.rb`

```ruby
class ScreeningPreset::ConditionExecutor
  # フィルタ可能なフィールド定義（ホワイトリスト）
  METRIC_RANGE_FIELDS = %i[
    revenue_yoy operating_income_yoy ordinary_income_yoy net_income_yoy eps_yoy
    roe roa operating_margin ordinary_margin net_margin
    free_cf consecutive_revenue_growth consecutive_profit_growth
  ].freeze

  METRIC_BOOLEAN_FIELDS = %i[
    operating_cf_positive investing_cf_negative free_cf_positive
  ].freeze

  DATA_JSON_RANGE_FIELDS = %i[
    per pbr psr dividend_yield ev_ebitda
    current_ratio debt_to_equity net_debt_to_equity
    asset_turnover gross_margin sga_ratio
    growth_score quality_score value_score composite_score
    revenue_cagr_3y revenue_cagr_5y operating_income_cagr_3y operating_income_cagr_5y
    net_income_cagr_3y net_income_cagr_5y eps_cagr_3y eps_cagr_5y
    payout_ratio dividend_growth_rate consecutive_dividend_growth
  ].freeze

  COMPANY_ATTRIBUTE_FIELDS = %i[
    sector_17_code sector_33_code market_code scale_category
  ].freeze

  attr_reader :conditions_json, :display_json

  def initialize(conditions_json:, display_json: {})
    @conditions_json = conditions_json.deep_symbolize_keys
    @display_json = display_json.deep_symbolize_keys
  end

  # 検索を実行し、結果を返す
  #
  # @return [Array<Hash>] { company:, metric:, display_values: {} }
  def execute
    scope = build_base_scope
    scope = apply_conditions(scope, @conditions_json)
    scope = apply_sort(scope)
    scope = apply_limit(scope)

    metrics = scope.includes(:company).to_a
    apply_post_filters(metrics)
  end

  # 基本スコープの構築
  def build_base_scope
    scope_type = @conditions_json[:scope_type] || "consolidated"
    period_type = @conditions_json[:period_type] || "annual"

    FinancialMetric
      .where(scope: scope_type, period_type: period_type)
      .latest_period
  end

  # 条件をスコープに適用（再帰的にAND/OR処理）
  def apply_conditions(scope, node)
    # nodeが配列の場合は各条件を処理
    # logic = "and" の場合はwhere連鎖
    # logic = "or" の場合はOR結合
    # 実装の詳細はPhase実装時に決定
  end

  private

  def apply_sort(scope)
    sort_by = @display_json[:sort_by]
    sort_order = @display_json[:sort_order] || "desc"
    # ホワイトリスト検証してorder適用
  end

  def apply_limit(scope)
    limit = @display_json[:limit] || 100
    scope.limit([limit, 500].min)  # 最大500件に制限
  end

  # SQLで表現しにくい条件（data_json_range, metric_top_n, preset_ref）はRubyレベルで処理
  def apply_post_filters(metrics)
    # data_json_range: metrics.select { |m| m.send(field) >= min && ... }
    # metric_top_n: metrics.sort_by { |m| m.send(field) }.first(n)
    # preset_ref: 参照先プリセットの結果との積集合
  end
end
```

### 設計判断

- **固定カラムのフィルタはSQL**で処理: DBインデックスを活用し効率的にフィルタ
- **data_json内の指標はRubyレベル**で処理: SQLiteのJSON関数は利用可能だがインデックスが効かないため、まず固定カラムで絞り込んだ後にRubyでフィルタする方が見通しがよい
- **metric_top_n** はRubyレベルでソート・スライス
- **preset_ref** は参照先プリセットを再帰的に実行し、結果のcompany_idの積集合（AND）または和集合（OR）をとる。循環参照を防ぐため深さ制限（最大3段）を設ける

---

## 4. ビルトインプリセットの定義

seedまたはrake taskで初期投入するビルトインプリセット:

### プリセット一覧

| 名前 | 条件概要 |
|------|---------|
| 連続増収増益（6期以上） | consecutive_revenue_growth >= 6 AND consecutive_profit_growth >= 6, sort: revenue_yoy desc |
| 高ROE・低PBR バリュー | roe >= 0.10 AND pbr <= 1.5 AND operating_cf_positive = true, sort: roe desc |
| 高成長グロース | revenue_yoy >= 0.15 AND operating_income_yoy >= 0.15, sort: composite_score desc |
| FCF プラス転換 | operating_cf_positive = true AND investing_cf_negative = true AND free_cf_positive = true, sort: free_cf desc |
| 高配当利回り | dividend_yield >= 0.03 AND operating_cf_positive = true, sort: dividend_yield desc |
| 総合スコアTOP100 | composite_score top 100, sort: composite_score desc |

---

## 5. コントローラー

### 5-1. Dashboard::SearchController

```ruby
# app/controllers/dashboard/search_controller.rb
class Dashboard::SearchController < DashboardController
  def index
    @presets = ScreeningPreset.enabled.order(execution_count: :desc)
  end

  # POST /dashboard/search/execute
  # Turbo Streamで結果テーブルを返す
  def execute
    conditions_json = parse_conditions_params
    display_json = parse_display_params

    executor = ScreeningPreset::ConditionExecutor.new(
      conditions_json: conditions_json,
      display_json: display_json
    )
    @results = executor.execute
    @display_columns = display_json[:columns] || default_display_columns

    respond_to do |format|
      format.turbo_stream
      format.json { render json: serialize_results(@results) }
    end
  end

  private

  def default_display_columns
    %w[securities_code name sector_33_name revenue_yoy operating_income_yoy roe composite_score]
  end
end
```

### 5-2. Dashboard::PresetsController

```ruby
# app/controllers/dashboard/presets_controller.rb
class Dashboard::PresetsController < DashboardController
  def index
    @presets = ScreeningPreset.enabled.order(updated_at: :desc)
  end

  def show
    @preset = ScreeningPreset.find(params[:id])
    executor = ScreeningPreset::ConditionExecutor.new(
      conditions_json: @preset.conditions_json,
      display_json: @preset.display_json
    )
    @results = executor.execute
    @preset.increment!(:execution_count)
    @preset.update!(last_executed_at: Time.current)
  end

  def create
    @preset = ScreeningPreset.new(preset_params)
    @preset.preset_type = :custom
    if @preset.save
      redirect_to dashboard_preset_path(@preset)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @preset = ScreeningPreset.find(params[:id])
    @preset.destroy if @preset.custom?
    redirect_to dashboard_presets_path
  end

  private

  def preset_params
    params.require(:screening_preset).permit(:name, :description, :conditions_json, :display_json)
  end
end
```

---

## 6. ビルトインプリセットのseed

```ruby
# db/seeds/screening_presets.rb（または db/seeds.rb に追記）
# rake db:seed で投入
# builtin タイプは冪等にupsert

ScreeningPreset.find_or_initialize_by(name: "連続増収増益（6期以上）", preset_type: :builtin).tap do |p|
  p.conditions_json = {
    scope_type: "consolidated", period_type: "annual", logic: "and",
    conditions: [
      { type: "metric_range", field: "consecutive_revenue_growth", min: 6 },
      { type: "metric_range", field: "consecutive_profit_growth", min: 6 },
    ]
  }
  p.display_json = {
    columns: %w[securities_code name sector_33_name consecutive_revenue_growth consecutive_profit_growth revenue_yoy operating_income_yoy],
    sort_by: "revenue_yoy", sort_order: "desc", limit: 100,
  }
  p.save!
end
# ... 他のビルトインプリセットも同様
```

---

## 7. テスト計画

### 7-1. ScreeningPreset::ConditionExecutor テスト

**ファイル**: `spec/models/screening_preset/condition_executor_spec.rb`

テスト項目:
- `#build_base_scope`: scope_type と period_type が正しく適用されること
- `#apply_conditions`: metric_range条件が正しくフィルタされること
- `#apply_conditions`: metric_boolean条件が正しくフィルタされること
- `#apply_conditions`: AND/OR論理演算が正しく動作すること
- `#execute`: data_json_range のポストフィルタが機能すること
- `#execute`: metric_top_n が正しくN件に制限すること
- `#execute`: preset_ref が再帰実行され結果が絞り込まれること
- `#execute`: preset_ref の循環参照で例外が発生しないこと（深さ制限テスト）

### 7-2. コントローラーテスト

テスティング規約に従い、コントローラーテストは記述しない。

---

## 8. ファイル構成

### 新規作成

| ファイル | 内容 |
|---------|------|
| `db/migrate/XXXXXXXX_create_screening_presets.rb` | テーブル作成 |
| `app/models/screening_preset.rb` | モデル |
| `app/models/screening_preset/condition_executor.rb` | 条件実行エンジン |
| `app/controllers/dashboard/search_controller.rb` | 検索コントローラー |
| `app/controllers/dashboard/presets_controller.rb` | プリセットコントローラー |
| `db/seeds/screening_presets.rb` | ビルトインプリセット |
| `spec/models/screening_preset/condition_executor_spec.rb` | テスト |

---

## 9. 実装順序

1. マイグレーション作成・実行
2. `ScreeningPreset` モデル実装
3. `ScreeningPreset::ConditionExecutor` 実装
4. ConditionExecutor テスト
5. `Dashboard::SearchController` 実装
6. `Dashboard::PresetsController` 実装
7. ビルトインプリセットseed作成・実行
8. 全テスト実行・確認
