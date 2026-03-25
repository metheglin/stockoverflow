# DEVELOP: WEBダッシュボード Phase 4 - 詳細ダッシュボード バックエンド

## 概要

特定企業の詳細ダッシュボードのバックエンド（コントローラー、データ集約ロジック、グラフ用JSON API）を実装する。

## 元計画

- `todo/20260325_1810_plan_web_dashboard_PLAN_done.md`

## 前提・依存

- Phase 1（基盤構築）が完了していること
- `dev_analysis_query_layer` (20260312_1000) の `Company::FinancialTimelineQuery` が利用可能であること
  - もし未完了の場合、本フェーズの実装時に最小実装を含める

---

## 1. 詳細ダッシュボードのデータ構造

企業詳細画面では以下のデータを提供する:

### 1-1. 企業基本情報

`Company` モデルから取得:
- 証券コード、企業名、英語名
- セクター（17分類・33分類）
- 市場区分
- 規模区分

### 1-2. 最新財務サマリー

最新の `FinancialValue` + `FinancialMetric` から取得:
- 売上高、営業利益、経常利益、純利益
- ROE, ROA, 営業利益率
- PER, PBR, 配当利回り
- 各種スコア (growth_score, quality_score, value_score, composite_score)
- FCF, 営業CF, 投資CF

### 1-3. 時系列データ（グラフ用）

`Company::FinancialTimelineQuery` を使って取得。以下のグラフに対応する複数の時系列データセットを構築する:

**グラフ種類:**

| グラフ | データ | グラフタイプ |
|--------|--------|------------|
| 売上・利益推移 | net_sales, operating_income, net_income | 複合（棒 + 折れ線） |
| 成長率推移 | revenue_yoy, operating_income_yoy, net_income_yoy | 折れ線 |
| 収益性指標推移 | roe, roa, operating_margin, net_margin | 折れ線 |
| キャッシュフロー推移 | operating_cf, investing_cf, financing_cf, free_cf | 棒グラフ（積み上げ） |
| バリュエーション推移 | per, pbr | 折れ線 |
| 1株あたり指標推移 | eps, bps | 折れ線 |

### 1-4. 株価データ

`DailyQuote` から取得:
- 直近の株価推移（チャート用）
- 移動平均線
- 出来高推移

### 1-5. セクター比較データ

`SectorMetric` を使い、同セクター内での相対的な位置づけを表示:
- セクター内パーセンタイル
- セクター平均・中央値との比較

---

## 2. データ集約クラス: Company::DashboardSummary

企業詳細画面に必要な全データを集約するクラス。

**配置先**: `app/models/company/dashboard_summary.rb`

```ruby
class Company::DashboardSummary
  attr_reader :company, :scope_type, :period_type

  def initialize(company:, scope_type: :consolidated, period_type: :annual)
    @company = company
    @scope_type = scope_type
    @period_type = period_type
  end

  # 最新のFinancialValue
  def latest_financial_value
    @latest_financial_value ||= load_latest_financial_value
  end

  # 最新のFinancialMetric
  def latest_financial_metric
    @latest_financial_metric ||= load_latest_financial_metric
  end

  # 時系列データ（FinancialTimelineQueryの結果）
  def timeline
    @timeline ||= load_timeline
  end

  # 直近の株価データ（デフォルト1年分）
  def recent_quotes
    @recent_quotes ||= load_recent_quotes
  end

  # セクター統計
  def sector_stats
    @sector_stats ||= load_sector_stats
  end

  # グラフ用JSONデータを構築
  # @param chart_type [Symbol] :revenue_profit, :growth_rates, :profitability, :cashflow, :valuation, :per_share
  # @return [Hash] Chart.jsのdata構造に対応するHash
  def get_chart_data(chart_type)
    case chart_type
    when :revenue_profit
      build_revenue_profit_chart
    when :growth_rates
      build_growth_rates_chart
    when :profitability
      build_profitability_chart
    when :cashflow
      build_cashflow_chart
    when :valuation
      build_valuation_chart
    when :per_share
      build_per_share_chart
    when :stock_price
      build_stock_price_chart
    end
  end

  # セクター内相対ポジションを返す
  # @return [Hash] { metric_key => { value:, sector_mean:, sector_median:, percentile: } }
  def get_sector_position
    return {} unless latest_financial_metric && sector_stats

    position = {}
    target_metrics = %i[roe roa operating_margin revenue_yoy per pbr dividend_yield]
    target_metrics.each do |key|
      value = read_metric_value(latest_financial_metric, key)
      stats = sector_stats&.dig(key.to_s)
      next unless value && stats

      position[key] = {
        value: value,
        sector_mean: stats["mean"],
        sector_median: stats["median"],
        percentile: SectorMetric.get_relative_position(value, stats),
      }
    end
    position
  end

  private

  def load_latest_financial_value
    FinancialValue
      .where(company_id: @company.id, scope: @scope_type, period_type: @period_type)
      .order(fiscal_year_end: :desc)
      .first
  end

  def load_latest_financial_metric
    FinancialMetric
      .where(company_id: @company.id, scope: @scope_type, period_type: @period_type)
      .order(fiscal_year_end: :desc)
      .first
  end

  def load_timeline
    Company::FinancialTimelineQuery.new(
      company: @company,
      scope_type: @scope_type,
      period_type: @period_type
    ).execute
  end

  def load_recent_quotes
    @company.daily_quotes
      .where("traded_on >= ?", 1.year.ago.to_date)
      .order(traded_on: :asc)
  end

  def load_sector_stats
    classification = :sector_33
    sector_code = @company.sector_33_code
    return nil unless sector_code

    latest_map = SectorMetric.load_latest_map(classification)
    latest_map[sector_code]&.data_json
  end

  # --- チャートデータ構築メソッド ---

  def build_revenue_profit_chart
    labels = timeline.map { |t| format_fiscal_label(t[:fiscal_year_end]) }
    {
      labels: labels,
      datasets: [
        { label: "売上高", data: timeline.map { |t| t[:values][:net_sales] }, type: "bar" },
        { label: "営業利益", data: timeline.map { |t| t[:values][:operating_income] }, type: "line" },
        { label: "純利益", data: timeline.map { |t| t[:values][:net_income] }, type: "line" },
      ]
    }
  end

  def build_growth_rates_chart
    labels = timeline.map { |t| format_fiscal_label(t[:fiscal_year_end]) }
    {
      labels: labels,
      datasets: [
        { label: "売上高成長率", data: timeline.map { |t| t[:metrics][:revenue_yoy] } },
        { label: "営業利益成長率", data: timeline.map { |t| t[:metrics][:operating_income_yoy] } },
        { label: "純利益成長率", data: timeline.map { |t| t[:metrics][:net_income_yoy] } },
      ]
    }
  end

  # 他のチャートビルダーも同様のパターン...

  def format_fiscal_label(date)
    "#{date.year}/#{date.month}"
  end

  def read_metric_value(metric, key)
    if metric.respond_to?(key)
      metric.send(key)
    else
      nil
    end
  end
end
```

---

## 3. コントローラー

### 3-1. Dashboard::CompaniesController

```ruby
# app/controllers/dashboard/companies_controller.rb
class Dashboard::CompaniesController < DashboardController
  def index
    @companies = Company.listed.order(:securities_code)
    if params[:q].present?
      q = "%#{params[:q]}%"
      @companies = @companies.where(
        "name LIKE ? OR securities_code LIKE ? OR name_english LIKE ?", q, q, q
      )
    end
    @companies = @companies.limit(100)
  end

  def show
    @company = Company.find(params[:id])
    @summary = Company::DashboardSummary.new(
      company: @company,
      scope_type: scope_type_param,
      period_type: period_type_param
    )
  end

  # Turbo Frameで財務データタブを返す
  def financials
    @company = Company.find(params[:id])
    @summary = Company::DashboardSummary.new(company: @company, scope_type: scope_type_param, period_type: period_type_param)
    render partial: "dashboard/companies/financials"
  end

  # Turbo Frameで指標タブを返す
  def metrics
    @company = Company.find(params[:id])
    @summary = Company::DashboardSummary.new(company: @company, scope_type: scope_type_param, period_type: period_type_param)
    render partial: "dashboard/companies/metrics"
  end

  # Turbo Frameで株価タブを返す
  def quotes
    @company = Company.find(params[:id])
    @summary = Company::DashboardSummary.new(company: @company, scope_type: scope_type_param, period_type: period_type_param)
    render partial: "dashboard/companies/quotes"
  end

  # 比較ビュー（複数指標の並列表示）
  def compare
    @company = Company.find(params[:id])
    @summary = Company::DashboardSummary.new(company: @company, scope_type: scope_type_param, period_type: period_type_param)
    @chart_types = (params[:charts] || "revenue_profit,growth_rates,profitability").split(",").map(&:to_sym)
  end

  private

  def scope_type_param
    params[:scope_type]&.to_sym || :consolidated
  end

  def period_type_param
    params[:period_type]&.to_sym || :annual
  end
end
```

### 3-2. JSON APIエンドポイント（グラフデータ）

Chart.jsにデータを供給するため、グラフデータをJSON形式で返すエンドポイントも提供する。
Turbo Frame内でJavaScriptがfetchしてChart.jsに渡すユースケースに対応。

ルーティングに追加:
```ruby
resources :companies, only: [:index, :show] do
  member do
    get :financials
    get :metrics
    get :quotes
    get :compare
    get :chart_data  # JSON API
  end
end
```

```ruby
# Dashboard::CompaniesControllerに追加
def chart_data
  @company = Company.find(params[:id])
  summary = Company::DashboardSummary.new(company: @company, scope_type: scope_type_param, period_type: period_type_param)
  chart_type = params[:chart_type]&.to_sym || :revenue_profit

  render json: summary.get_chart_data(chart_type)
end
```

---

## 4. テスト計画

### 4-1. Company::DashboardSummary テスト

**ファイル**: `spec/models/company/dashboard_summary_spec.rb`

テスト項目:
- `#get_chart_data(:revenue_profit)`: labels と datasets が正しい構造で返ること
- `#get_chart_data(:growth_rates)`: 成長率の時系列データが含まれること
- `#get_sector_position`: セクター内相対ポジションが正しく計算されること
- `#get_sector_position`: セクター統計がない場合に空Hashを返すこと

### 4-2. コントローラーテスト

テスティング規約に従い、コントローラーテストは記述しない。

---

## 5. ファイル構成

### 新規作成

| ファイル | 内容 |
|---------|------|
| `app/models/company/dashboard_summary.rb` | 詳細画面データ集約 |
| `app/controllers/dashboard/companies_controller.rb` | 企業コントローラー |
| `spec/models/company/dashboard_summary_spec.rb` | テスト |

### 既存変更

| ファイル | 変更内容 |
|---------|---------|
| `config/routes.rb` | 企業詳細ルーティング追加（Phase 1で定義済みだが、chart_data追加） |

---

## 6. 実装順序

1. `Company::DashboardSummary` 実装（チャートデータ構築含む）
2. DashboardSummary テスト
3. `Dashboard::CompaniesController` 実装
4. JSON API (chart_data) 実装
5. ルーティング調整
6. 動作確認
