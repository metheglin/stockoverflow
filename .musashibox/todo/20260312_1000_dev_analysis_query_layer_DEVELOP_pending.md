# DEVELOP: 分析クエリレイヤー実装

## 概要

蓄積された `companies`, `financial_values`, `financial_metrics`, `daily_quotes` のデータを分析・活用するためのクエリインターフェースを実装する。CLAUDE.mdに記載された3つのユースケースへの対応と、将来の拡張に耐えうる汎用的な仕組みを構築する。

---

## 1. FinancialMetric scope の追加

`app/models/financial_metric.rb` に以下の scope を追加する。

### 1-1. 基本的なフィルタ scope

```ruby
# 連結決算のみ（分析の基本はほぼ連結）
scope :consolidated_annual, -> { consolidated.annual }

# 最新期の指標のみ取得（企業ごとに最新の fiscal_year_end を持つレコード）
scope :latest_period, -> {
  where(
    "fiscal_year_end = (SELECT MAX(fm2.fiscal_year_end) FROM financial_metrics fm2 " \
    "WHERE fm2.company_id = financial_metrics.company_id " \
    "AND fm2.scope = financial_metrics.scope " \
    "AND fm2.period_type = financial_metrics.period_type)"
  )
}
```

### 1-2. ユースケース1用 scope: 連続増収増益フィルタ

```ruby
# 指定期数以上の連続増収増益企業を取得
#
# 使い方:
#   FinancialMetric.consolidated_annual.latest_period
#     .consecutive_growth(min_periods: 6)
#     .order(revenue_yoy: :desc)
#     .includes(:company)
#
scope :consecutive_growth, ->(min_periods:) {
  where("consecutive_revenue_growth >= ?", min_periods)
    .where("consecutive_profit_growth >= ?", min_periods)
}
```

- `consecutive_revenue_growth` / `consecutive_profit_growth` には既にDBインデックスが付与済み
- `latest_period` と組み合わせることで「現在の最新期時点で N期連続増収増益」を取得可能

### 1-3. ユースケース2用 scope: CF条件フィルタ

```ruby
# 営業CF正・投資CF負の企業
scope :healthy_cf, -> {
  where(operating_cf_positive: true, investing_cf_negative: true)
}
```

---

## 2. Company scope の追加

`app/models/company.rb` に以下の scope を追加する。

```ruby
# セクターによるフィルタ
scope :by_sector_17, ->(code) { where(sector_17_code: code) }
scope :by_sector_33, ->(code) { where(sector_33_code: code) }

# 市場区分によるフィルタ
scope :by_market, ->(code) { where(market_code: code) }
```

---

## 3. QueryObject クラスの設計・実装

### 3-1. Company::ConsecutiveGrowthQuery（ユースケース1）

**配置先**: `app/models/company/consecutive_growth_query.rb`

**目的**: N期連続増収増益の企業を一覧し、増収率順にソートして返す。

```ruby
class Company::ConsecutiveGrowthQuery
  attr_reader :min_periods, :scope_type, :period_type, :sector_33_code, :market_code, :limit

  # @param min_periods [Integer] 最低連続増収増益期数（デフォルト: 6）
  # @param scope_type [Symbol] :consolidated or :non_consolidated（デフォルト: :consolidated）
  # @param period_type [Symbol] :annual, :q1, :q2, :q3（デフォルト: :annual）
  # @param sector_33_code [String, nil] 33業種コードでフィルタ
  # @param market_code [String, nil] 市場区分コードでフィルタ
  # @param limit [Integer, nil] 取得件数上限
  def initialize(min_periods: 6, scope_type: :consolidated, period_type: :annual,
                 sector_33_code: nil, market_code: nil, limit: nil)
    @min_periods = min_periods
    @scope_type = scope_type
    @period_type = period_type
    @sector_33_code = sector_33_code
    @market_code = market_code
    @limit = limit
  end

  # クエリを実行し、結果を返す
  #
  # @return [Array<Hash>] 企業情報と指標のHash配列
  #
  # 返却例:
  #   [
  #     {
  #       company: #<Company>,
  #       metric: #<FinancialMetric>,
  #       consecutive_revenue_growth: 8,
  #       consecutive_profit_growth: 7,
  #       revenue_yoy: 0.2345,
  #     },
  #     ...
  #   ]
  #
  def execute
    metrics = build_metrics_scope
    metrics.map do |metric|
      {
        company: metric.company,
        metric: metric,
        consecutive_revenue_growth: metric.consecutive_revenue_growth,
        consecutive_profit_growth: metric.consecutive_profit_growth,
        revenue_yoy: metric.revenue_yoy,
      }
    end
  end

  private

  def build_metrics_scope
    scope = FinancialMetric
      .where(scope: @scope_type, period_type: @period_type)
      .latest_period
      .consecutive_growth(min_periods: @min_periods)
      .includes(:company)
      .order(revenue_yoy: :desc)

    if @sector_33_code || @market_code
      scope = scope.joins(:company)
      scope = scope.where(companies: { sector_33_code: @sector_33_code }) if @sector_33_code
      scope = scope.where(companies: { market_code: @market_code }) if @market_code
    end

    scope = scope.limit(@limit) if @limit
    scope
  end
end
```

### 3-2. Company::CashFlowTurnaroundQuery（ユースケース2）

**配置先**: `app/models/company/cash_flow_turnaround_query.rb`

**目的**: 営業CF正・投資CF負の企業のうち、フリーCFがマイナスからプラスに転換した企業を検出する。

```ruby
class Company::CashFlowTurnaroundQuery
  attr_reader :scope_type, :period_type, :sector_33_code, :market_code, :limit

  # @param scope_type [Symbol] :consolidated or :non_consolidated（デフォルト: :consolidated）
  # @param period_type [Symbol] :annual, :q1, :q2, :q3（デフォルト: :annual）
  # @param sector_33_code [String, nil] 33業種コードでフィルタ
  # @param market_code [String, nil] 市場区分コードでフィルタ
  # @param limit [Integer, nil] 取得件数上限
  def initialize(scope_type: :consolidated, period_type: :annual,
                 sector_33_code: nil, market_code: nil, limit: nil)
    @scope_type = scope_type
    @period_type = period_type
    @sector_33_code = sector_33_code
    @market_code = market_code
    @limit = limit
  end

  # クエリを実行し、フリーCF転換企業を返す
  #
  # @return [Array<Hash>] 企業情報と当期・前期指標のHash配列
  #
  # 返却例:
  #   [
  #     {
  #       company: #<Company>,
  #       current_metric: #<FinancialMetric>,
  #       previous_metric: #<FinancialMetric>,
  #       current_free_cf: 500_000_000,
  #       previous_free_cf: -200_000_000,
  #     },
  #     ...
  #   ]
  #
  def execute
    current_metrics = build_current_metrics_scope.to_a
    results = []

    current_metrics.each do |current|
      previous = load_previous_metric(current)
      next unless previous
      next unless previous.free_cf_positive == false

      results << {
        company: current.company,
        current_metric: current,
        previous_metric: previous,
        current_free_cf: current.free_cf,
        previous_free_cf: previous.free_cf,
      }
    end

    results = results.first(@limit) if @limit
    results
  end

  # 前期の FinancialMetric を検索する
  #
  # fiscal_year_end の約1年前（±1ヶ月）の範囲で検索
  #
  # @param metric [FinancialMetric] 当期の指標
  # @return [FinancialMetric, nil]
  def load_previous_metric(metric)
    prev_start = metric.fiscal_year_end - 13.months
    prev_end = metric.fiscal_year_end - 11.months

    FinancialMetric
      .where(
        company_id: metric.company_id,
        scope: metric.scope,
        period_type: metric.period_type,
        fiscal_year_end: prev_start..prev_end,
      )
      .order(fiscal_year_end: :desc)
      .first
  end

  private

  def build_current_metrics_scope
    scope = FinancialMetric
      .where(scope: @scope_type, period_type: @period_type)
      .latest_period
      .healthy_cf
      .where(free_cf_positive: true)
      .includes(:company)
      .order(:company_id)

    if @sector_33_code || @market_code
      scope = scope.joins(:company)
      scope = scope.where(companies: { sector_33_code: @sector_33_code }) if @sector_33_code
      scope = scope.where(companies: { market_code: @market_code }) if @market_code
    end

    scope
  end
end
```

**設計判断**: 前期との比較はSQLの自己結合でも表現可能だが、SQLiteのパフォーマンスとコードの明快さを考慮し、Rubyレベルで前期検索を行う設計とする。`load_previous_metric` は公開メソッドとして直接テスト可能。

### 3-3. Company::FinancialTimelineQuery（ユースケース3）

**配置先**: `app/models/company/financial_timeline_query.rb`

**目的**: 特定企業の財務データ・指標の時系列推移を取得し、トレンド転換を可視化するためのデータを返す。

```ruby
class Company::FinancialTimelineQuery
  attr_reader :company, :scope_type, :period_type, :from_year_end, :to_year_end

  # @param company [Company] 対象企業
  # @param scope_type [Symbol] :consolidated or :non_consolidated（デフォルト: :consolidated）
  # @param period_type [Symbol] :annual, :q1, :q2, :q3（デフォルト: :annual）
  # @param from_year_end [Date, nil] 取得開始の fiscal_year_end
  # @param to_year_end [Date, nil] 取得終了の fiscal_year_end
  def initialize(company:, scope_type: :consolidated, period_type: :annual,
                 from_year_end: nil, to_year_end: nil)
    @company = company
    @scope_type = scope_type
    @period_type = period_type
    @from_year_end = from_year_end
    @to_year_end = to_year_end
  end

  # 時系列データを取得する
  #
  # @return [Array<Hash>] 期ごとの財務数値・指標のHash配列（fiscal_year_end昇順）
  #
  # 返却例:
  #   [
  #     {
  #       fiscal_year_end: Date.new(2022, 3, 31),
  #       financial_value: #<FinancialValue>,
  #       financial_metric: #<FinancialMetric>,  # nil の場合あり
  #       values: {
  #         net_sales: 100_000_000,
  #         operating_income: 10_000_000,
  #         ...
  #       },
  #       metrics: {
  #         revenue_yoy: 0.15,
  #         roe: 0.12,
  #         consecutive_revenue_growth: 3,
  #         ...
  #       },
  #     },
  #     ...
  #   ]
  #
  def execute
    values = load_financial_values
    metrics_map = load_financial_metrics_map

    values.map do |fv|
      metric = metrics_map[fv.fiscal_year_end]
      {
        fiscal_year_end: fv.fiscal_year_end,
        financial_value: fv,
        financial_metric: metric,
        values: extract_values(fv),
        metrics: metric ? extract_metrics(metric) : {},
      }
    end
  end

  # 財務数値を抽出する
  #
  # @param fv [FinancialValue]
  # @return [Hash] 主要財務数値のHash
  def extract_values(fv)
    {
      net_sales: fv.net_sales,
      operating_income: fv.operating_income,
      ordinary_income: fv.ordinary_income,
      net_income: fv.net_income,
      eps: fv.eps,
      bps: fv.bps,
      total_assets: fv.total_assets,
      net_assets: fv.net_assets,
      equity_ratio: fv.equity_ratio,
      operating_cf: fv.operating_cf,
      investing_cf: fv.investing_cf,
      financing_cf: fv.financing_cf,
      cash_and_equivalents: fv.cash_and_equivalents,
    }
  end

  # 指標を抽出する
  #
  # @param metric [FinancialMetric]
  # @return [Hash] 主要指標のHash
  def extract_metrics(metric)
    result = {
      revenue_yoy: metric.revenue_yoy,
      operating_income_yoy: metric.operating_income_yoy,
      net_income_yoy: metric.net_income_yoy,
      roe: metric.roe,
      roa: metric.roa,
      operating_margin: metric.operating_margin,
      net_margin: metric.net_margin,
      free_cf: metric.free_cf,
      free_cf_positive: metric.free_cf_positive,
      consecutive_revenue_growth: metric.consecutive_revenue_growth,
      consecutive_profit_growth: metric.consecutive_profit_growth,
    }

    # data_json のバリュエーション指標も含める
    if metric.data_json.present?
      result[:per] = metric.per
      result[:pbr] = metric.pbr
      result[:psr] = metric.psr
      result[:dividend_yield] = metric.dividend_yield
    end

    result
  end

  private

  def load_financial_values
    scope = FinancialValue
      .where(company_id: @company.id, scope: @scope_type, period_type: @period_type)
      .order(fiscal_year_end: :asc)

    scope = scope.where("fiscal_year_end >= ?", @from_year_end) if @from_year_end
    scope = scope.where("fiscal_year_end <= ?", @to_year_end) if @to_year_end
    scope
  end

  def load_financial_metrics_map
    scope = FinancialMetric
      .where(company_id: @company.id, scope: @scope_type, period_type: @period_type)

    scope = scope.where("fiscal_year_end >= ?", @from_year_end) if @from_year_end
    scope = scope.where("fiscal_year_end <= ?", @to_year_end) if @to_year_end

    scope.index_by(&:fiscal_year_end)
  end
end
```

---

## 4. 汎用フィルタ・ソート: Company::ScreeningQuery

**配置先**: `app/models/company/screening_query.rb`

**目的**: 将来追加されるユースケースに対応しやすい、パラメータベースの汎用スクリーニングクエリ。

```ruby
class Company::ScreeningQuery
  # フィルタ・ソート可能なカラム定義
  METRIC_FILTER_COLUMNS = %i[
    revenue_yoy operating_income_yoy net_income_yoy eps_yoy
    roe roa operating_margin net_margin
    consecutive_revenue_growth consecutive_profit_growth
    free_cf
  ].freeze

  METRIC_BOOLEAN_COLUMNS = %i[
    operating_cf_positive investing_cf_negative free_cf_positive
  ].freeze

  METRIC_SORTABLE_COLUMNS = (METRIC_FILTER_COLUMNS + %i[fiscal_year_end]).freeze

  attr_reader :filters, :sort_by, :sort_order, :scope_type, :period_type,
              :sector_33_code, :market_code, :limit, :offset

  # @param filters [Hash] フィルタ条件のHash
  #   キー: METRIC_FILTER_COLUMNS or METRIC_BOOLEAN_COLUMNS のカラム名
  #   値: { min: N, max: N } (数値) or true/false (boolean)
  #   例: { roe: { min: 0.1 }, operating_cf_positive: true, consecutive_revenue_growth: { min: 3 } }
  # @param sort_by [Symbol] ソートカラム（METRIC_SORTABLE_COLUMNS のいずれか）
  # @param sort_order [Symbol] :asc or :desc（デフォルト: :desc）
  # @param scope_type [Symbol] :consolidated or :non_consolidated（デフォルト: :consolidated）
  # @param period_type [Symbol] :annual, :q1, :q2, :q3（デフォルト: :annual）
  # @param sector_33_code [String, nil] 33業種コードでフィルタ
  # @param market_code [String, nil] 市場区分コードでフィルタ
  # @param limit [Integer, nil] 取得件数上限
  # @param offset [Integer, nil] オフセット
  def initialize(filters: {}, sort_by: :revenue_yoy, sort_order: :desc,
                 scope_type: :consolidated, period_type: :annual,
                 sector_33_code: nil, market_code: nil, limit: nil, offset: nil)
    @filters = filters
    @sort_by = sort_by
    @sort_order = sort_order
    @scope_type = scope_type
    @period_type = period_type
    @sector_33_code = sector_33_code
    @market_code = market_code
    @limit = limit
    @offset = offset
  end

  # クエリを実行し、結果を返す
  #
  # @return [Array<Hash>] 企業情報と指標のHash配列
  def execute
    metrics = build_scope
    metrics.map do |metric|
      {
        company: metric.company,
        metric: metric,
      }
    end
  end

  # フィルタ条件を適用したActiveRecord::Relationを返す（テスト・拡張用）
  #
  # @return [ActiveRecord::Relation]
  def build_scope
    scope = FinancialMetric
      .where(scope: @scope_type, period_type: @period_type)
      .latest_period
      .includes(:company)

    scope = apply_filters(scope)
    scope = apply_company_filters(scope)
    scope = apply_sort(scope)
    scope = scope.limit(@limit) if @limit
    scope = scope.offset(@offset) if @offset
    scope
  end

  # フィルタ条件を適用する
  #
  # @param scope [ActiveRecord::Relation]
  # @return [ActiveRecord::Relation]
  def apply_filters(scope)
    @filters.each do |column, condition|
      column_sym = column.to_sym

      if METRIC_BOOLEAN_COLUMNS.include?(column_sym)
        scope = scope.where(column_sym => condition)
      elsif METRIC_FILTER_COLUMNS.include?(column_sym)
        scope = scope.where("#{column_sym} >= ?", condition[:min]) if condition[:min]
        scope = scope.where("#{column_sym} <= ?", condition[:max]) if condition[:max]
      end
    end

    scope
  end

  private

  def apply_company_filters(scope)
    if @sector_33_code || @market_code
      scope = scope.joins(:company)
      scope = scope.where(companies: { sector_33_code: @sector_33_code }) if @sector_33_code
      scope = scope.where(companies: { market_code: @market_code }) if @market_code
    end
    scope
  end

  def apply_sort(scope)
    if METRIC_SORTABLE_COLUMNS.include?(@sort_by)
      scope.order(@sort_by => @sort_order)
    else
      scope.order(revenue_yoy: :desc)
    end
  end
end
```

---

## 5. DBインデックスの追加

現在のスキーマを検証した結果、追加が必要なインデックス:

### 5-1. financial_metrics 複合インデックス

ユースケース2のCF転換クエリにおいて、boolean カラムの組み合わせでフィルタが発生するため、複合インデックスを追加する。

```ruby
# db/migrate/XXXXXXXXXX_add_cf_index_to_financial_metrics.rb
class AddCfIndexToFinancialMetrics < ActiveRecord::Migration[8.1]
  def change
    add_index :financial_metrics,
              [:operating_cf_positive, :investing_cf_negative, :free_cf_positive],
              name: "idx_fin_metrics_cf_conditions"
  end
end
```

### 5-2. financial_values にインデックス追加は不要

現在のインデックス構成を確認:
- `idx_fin_values_unique` (company_id, fiscal_year_end, scope, period_type) - ユニーク
- `index_financial_values_on_company_id`
- `index_financial_values_on_financial_report_id`
- `index_financial_values_on_fiscal_year_end`

→ FinancialTimelineQuery の検索パターン（company_id + scope + period_type + fiscal_year_end範囲）は `idx_fin_values_unique` のプレフィックスで対応可能。追加不要。

### 5-3. companies にセクター・市場インデックス追加

スクリーニングで頻繁にセクター・市場でフィルタされるため:

```ruby
# 上記と同じマイグレーションファイルに含める
add_index :companies, :sector_33_code, name: "index_companies_on_sector_33_code"
add_index :companies, :market_code, name: "index_companies_on_market_code"
```

---

## 6. テスト計画

### 6-1. FinancialMetric scope テスト

**ファイル**: `spec/models/financial_metric_spec.rb`（既存ファイルに追加）

テスティング規約に従い、scopeのテストは記述しない。追加されるクラスメソッドが存在する場合のみテスト対象とする。本件ではscopeのみの追加のため、FinancialMetricモデルへのテスト追加は不要。

### 6-2. Company::ConsecutiveGrowthQuery テスト

**ファイル**: `spec/models/company/consecutive_growth_query_spec.rb`

テスト項目:
- `#execute`: min_periods=6 で該当企業が返ること（DBにデータ作成が必要）
- `#execute`: revenue_yoy降順でソートされること
- `#execute`: 該当なしの場合空配列が返ること
- `#execute`: sector_33_codeフィルタが機能すること

### 6-3. Company::CashFlowTurnaroundQuery テスト

**ファイル**: `spec/models/company/cash_flow_turnaround_query_spec.rb`

テスト項目:
- `#load_previous_metric`: 前期指標を正しく検索すること
- `#load_previous_metric`: 前期データがない場合にnilを返すこと
- `#execute`: 前期free_cf_positive=false、当期free_cf_positive=trueの企業が返ること
- `#execute`: 前期もfree_cf_positive=trueの企業は返らないこと

### 6-4. Company::FinancialTimelineQuery テスト

**ファイル**: `spec/models/company/financial_timeline_query_spec.rb`

テスト項目:
- `#extract_values`: FinancialValueの主要カラムが全て含まれること
- `#extract_metrics`: FinancialMetricの主要カラムとdata_json指標が含まれること
- `#execute`: fiscal_year_end昇順で返ること
- `#execute`: from_year_end / to_year_end による期間フィルタが機能すること

### 6-5. Company::ScreeningQuery テスト

**ファイル**: `spec/models/company/screening_query_spec.rb`

テスト項目:
- `#apply_filters`: 数値条件（min/max）が正しく適用されること
- `#apply_filters`: boolean条件が正しく適用されること
- `#build_scope`: ソート条件が正しく適用されること
- `#build_scope`: 不正なソートカラム指定時にデフォルトソートが使われること
- `#execute`: limit / offset が機能すること

---

## 7. ファイル構成

### 新規作成

| ファイル | 内容 |
|---------|------|
| `app/models/company/consecutive_growth_query.rb` | 連続増収増益企業スクリーニング |
| `app/models/company/cash_flow_turnaround_query.rb` | CF転換企業検出 |
| `app/models/company/financial_timeline_query.rb` | 企業別時系列データ取得 |
| `app/models/company/screening_query.rb` | 汎用スクリーニング |
| `db/migrate/XXXXXXXX_add_analysis_indexes.rb` | 分析用インデックス追加 |
| `spec/models/company/consecutive_growth_query_spec.rb` | ConsecutiveGrowthQuery テスト |
| `spec/models/company/cash_flow_turnaround_query_spec.rb` | CashFlowTurnaroundQuery テスト |
| `spec/models/company/financial_timeline_query_spec.rb` | FinancialTimelineQuery テスト |
| `spec/models/company/screening_query_spec.rb` | ScreeningQuery テスト |

### 既存変更

| ファイル | 変更内容 |
|---------|---------|
| `app/models/financial_metric.rb` | scope 3件追加（consolidated_annual, latest_period, consecutive_growth, healthy_cf） |
| `app/models/company.rb` | scope 3件追加（by_sector_17, by_sector_33, by_market） |

---

## 8. 実装順序

1. マイグレーション実行（インデックス追加）
2. FinancialMetric scope 追加
3. Company scope 追加
4. Company::ConsecutiveGrowthQuery 実装 + テスト
5. Company::CashFlowTurnaroundQuery 実装 + テスト
6. Company::FinancialTimelineQuery 実装 + テスト
7. Company::ScreeningQuery 実装 + テスト
8. 全テスト実行・確認

---

## 9. 設計判断の根拠

### QueryObject の配置先

- `app/models/company/` 配下に配置。`Company` を軸とした分析であることを明示し、Railsの自動読み込みに対応。
- `Query` suffixを付与（rails.mdの規約に準拠）。

### SQLの自己結合 vs Rubyレベルの前期比較

- ユースケース2（CF転換）では前期データとの比較が必要
- SQLiteの自己結合はパフォーマンスが読みにくく、日付範囲（±1ヶ月）の前期検索ロジックが既に `CalculateFinancialMetricsJob` にRuby実装として存在する
- テスタビリティの観点からも、前期検索を公開メソッドとしてRubyで実装する方が有利
- 想定データ量（最新期の企業数は最大約4,000件）でN+1クエリのコストは十分許容範囲

### latest_period scope の実装方式

- サブクエリ方式を採用。`WHERE fiscal_year_end = (SELECT MAX(...) ...)` で企業ごとの最新期を効率的に取得。
- `idx_fin_metrics_unique` インデックスのプレフィックス（company_id）を活用できる。

### 汎用 ScreeningQuery の設計方針

- ホワイトリスト方式: `METRIC_FILTER_COLUMNS` / `METRIC_BOOLEAN_COLUMNS` に定義されたカラムのみフィルタ可能とし、SQLインジェクションを防止。
- フィルタ条件のHashインターフェースは、将来のWeb API（`GET /api/v1/screening?roe_min=0.1&operating_cf_positive=true`）のパラメータと自然に対応する。
