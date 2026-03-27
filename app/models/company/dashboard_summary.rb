class Company::DashboardSummary
  CHART_TYPES = %i[
    revenue_profit growth_rates growth_acceleration profitability cashflow valuation per_share stock_price
  ].freeze

  QUOTE_PERIODS = {
    "1m" => 1.month,
    "3m" => 3.months,
    "6m" => 6.months,
    "1y" => 1.year,
    "3y" => 3.years,
  }.freeze

  attr_reader :company, :scope_type, :period_type, :quote_period

  def initialize(company:, scope_type: :consolidated, period_type: :annual, quote_period: nil)
    @company = company
    @scope_type = scope_type
    @period_type = period_type
    @quote_period = quote_period
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
  #
  # @param chart_type [Symbol] :revenue_profit, :growth_rates, :profitability, :cashflow, :valuation, :per_share, :stock_price
  # @return [Hash] Chart.jsのdata構造に対応するHash
  def get_chart_data(chart_type)
    case chart_type
    when :revenue_profit
      build_revenue_profit_chart
    when :growth_rates
      build_growth_rates_chart
    when :growth_acceleration
      build_growth_acceleration_chart
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
  #
  # @return [Hash] { metric_key => { value:, sector_mean:, sector_median:, percentile:, exact_percentile: } }
  def get_sector_position
    return {} unless latest_financial_metric && sector_stats

    # パーセンタイルキー → メトリクスキーの逆引きマップ
    exact_percentile_map = FinancialMetric::SECTOR_PERCENTILE_TARGETS.invert

    position = {}
    target_metrics = %i[roe roa operating_margin revenue_yoy per pbr dividend_yield]
    target_metrics.each do |key|
      value = read_metric_value(latest_financial_metric, key)
      stats = sector_stats&.dig(key.to_s)
      next unless value && stats

      # 正確なパーセンタイル値（data_jsonに格納済みの場合）
      percentile_key = exact_percentile_map.key(key)
      exact_pct = percentile_key ? latest_financial_metric.public_send(percentile_key) : nil

      position[key] = {
        value: value,
        sector_mean: stats["mean"],
        sector_median: stats["median"],
        percentile: SectorMetric.get_relative_position(value, stats),
        exact_percentile: exact_pct&.to_f,
      }
    end
    position
  end

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
    duration = QUOTE_PERIODS[@quote_period.to_s] || 1.year
    if @quote_period.to_s == "all"
      @company.daily_quotes.order(traded_on: :asc)
    else
      @company.daily_quotes
        .where("traded_on >= ?", duration.ago.to_date)
        .order(traded_on: :asc)
    end
  end

  def load_sector_stats
    sector_code = @company.sector_33_code
    return nil unless sector_code

    latest_map = SectorMetric.load_latest_map(:sector_33)
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

  def build_growth_acceleration_chart
    labels = timeline.map { |t| format_fiscal_label(t[:fiscal_year_end]) }
    {
      labels: labels,
      datasets: [
        { label: "売上高加速度", data: timeline.map { |t| t[:metrics][:revenue_growth_acceleration] }, type: "bar" },
        { label: "営業利益加速度", data: timeline.map { |t| t[:metrics][:operating_income_growth_acceleration] }, type: "bar" },
        { label: "純利益加速度", data: timeline.map { |t| t[:metrics][:net_income_growth_acceleration] }, type: "bar" },
        { label: "EPS加速度", data: timeline.map { |t| t[:metrics][:eps_growth_acceleration] }, type: "bar" },
      ]
    }
  end

  def build_profitability_chart
    labels = timeline.map { |t| format_fiscal_label(t[:fiscal_year_end]) }
    {
      labels: labels,
      datasets: [
        { label: "ROE", data: timeline.map { |t| t[:metrics][:roe] } },
        { label: "ROA", data: timeline.map { |t| t[:metrics][:roa] } },
        { label: "営業利益率", data: timeline.map { |t| t[:metrics][:operating_margin] } },
        { label: "純利益率", data: timeline.map { |t| t[:metrics][:net_margin] } },
      ]
    }
  end

  def build_cashflow_chart
    labels = timeline.map { |t| format_fiscal_label(t[:fiscal_year_end]) }
    {
      labels: labels,
      datasets: [
        { label: "営業CF", data: timeline.map { |t| t[:values][:operating_cf] }, type: "bar" },
        { label: "投資CF", data: timeline.map { |t| t[:values][:investing_cf] }, type: "bar" },
        { label: "財務CF", data: timeline.map { |t| t[:values][:financing_cf] }, type: "bar" },
        { label: "フリーCF", data: timeline.map { |t| t[:metrics][:free_cf] }, type: "bar" },
      ]
    }
  end

  def build_valuation_chart
    labels = timeline.map { |t| format_fiscal_label(t[:fiscal_year_end]) }
    {
      labels: labels,
      datasets: [
        { label: "PER", data: timeline.map { |t| t[:metrics][:per] } },
        { label: "PBR", data: timeline.map { |t| t[:metrics][:pbr] } },
      ]
    }
  end

  def build_per_share_chart
    labels = timeline.map { |t| format_fiscal_label(t[:fiscal_year_end]) }
    {
      labels: labels,
      datasets: [
        { label: "EPS", data: timeline.map { |t| t[:values][:eps] } },
        { label: "BPS", data: timeline.map { |t| t[:values][:bps] } },
      ]
    }
  end

  def build_stock_price_chart
    quotes = recent_quotes.to_a
    return { labels: [], datasets: [] } if quotes.empty?

    labels = quotes.map { |q| q.traded_on.strftime("%Y/%m/%d") }
    prices = quotes.map { |q| q.adjusted_close || q.close_price }

    mas = {}
    [25, 75].each do |window|
      mas[window] = quotes.each_with_index.map do |_q, i|
        if i + 1 >= window
          slice = quotes[(i + 1 - window)..i]
          slice_prices = slice.map { |sq| sq.adjusted_close || sq.close_price }
          if slice_prices.all?
            (slice_prices.sum.to_d / window).round(2).to_f
          end
        end
      end
    end

    datasets = [
      { label: "株価", data: prices, type: "line" },
    ]
    datasets << { label: "25日MA", data: mas[25], type: "line" } if mas[25]
    datasets << { label: "75日MA", data: mas[75], type: "line" } if mas[75]

    {
      labels: labels,
      datasets: datasets,
    }
  end

  def format_fiscal_label(date)
    return nil unless date
    "#{date.year}/#{date.month}"
  end

  def read_metric_value(metric, key)
    metric.public_send(key)
  rescue NoMethodError
    nil
  end
end
