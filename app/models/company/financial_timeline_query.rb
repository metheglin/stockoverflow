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
  #       financial_metric: #<FinancialMetric>,
  #       values: { net_sales: 100_000_000, ... },
  #       metrics: { revenue_yoy: 0.15, roe: 0.12, ... },
  #     },
  #     ...
  #   ]
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
      # 成長加速度
      result[:revenue_growth_acceleration] = metric.revenue_growth_acceleration
      result[:operating_income_growth_acceleration] = metric.operating_income_growth_acceleration
      result[:net_income_growth_acceleration] = metric.net_income_growth_acceleration
      result[:eps_growth_acceleration] = metric.eps_growth_acceleration
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
