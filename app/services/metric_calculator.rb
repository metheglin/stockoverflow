class MetricCalculator
  def initialize(company)
    @company = company
  end

  # Calculate and save all metrics for a given fiscal period
  def calculate_all_metrics(fiscal_year:, fiscal_period:)
    statement = @company.financial_statements.find_by(
      fiscal_year: fiscal_year,
      fiscal_period: fiscal_period
    )

    return unless statement

    calculate_profitability_metrics(statement)
    calculate_growth_metrics(statement)
    calculate_cash_flow_metrics(statement)
  end

  # Calculate profitability metrics (ROE, ROA, margins)
  def calculate_profitability_metrics(statement)
    metric = ProfitabilityMetric.find_or_initialize_by(
      company: @company,
      fiscal_year: statement.fiscal_year,
      fiscal_period: statement.fiscal_period
    )

    # ROE = Net Income / Total Equity
    metric.roe = calculate_ratio(statement.net_income, statement.total_equity)

    # ROA = Net Income / Total Assets
    metric.roa = calculate_ratio(statement.net_income, statement.total_assets)

    # Operating Margin = Operating Income / Net Sales
    metric.operating_margin = calculate_ratio(statement.operating_income, statement.net_sales)

    # Net Margin = Net Income / Net Sales
    metric.net_margin = calculate_ratio(statement.net_income, statement.net_sales)

    metric.save!
    metric
  end

  # Calculate growth metrics (YoY growth rates)
  def calculate_growth_metrics(statement)
    prev_statement = find_previous_statement(statement)
    return unless prev_statement

    metric = GrowthMetric.find_or_initialize_by(
      company: @company,
      fiscal_year: statement.fiscal_year,
      fiscal_period: statement.fiscal_period
    )

    # Revenue Growth Rate
    metric.revenue_growth_rate = calculate_growth_rate(
      prev_statement.net_sales,
      statement.net_sales
    )

    # Operating Income Growth Rate
    metric.operating_income_growth_rate = calculate_growth_rate(
      prev_statement.operating_income,
      statement.operating_income
    )

    # Net Income Growth Rate
    metric.net_income_growth_rate = calculate_growth_rate(
      prev_statement.net_income,
      statement.net_income
    )

    # Total Assets Growth Rate
    metric.total_assets_growth_rate = calculate_growth_rate(
      prev_statement.total_assets,
      statement.total_assets
    )

    metric.save!
    metric
  end

  # Calculate cash flow metrics
  def calculate_cash_flow_metrics(statement)
    metric = CashFlowMetric.find_or_initialize_by(
      company: @company,
      fiscal_year: statement.fiscal_year,
      fiscal_period: statement.fiscal_period
    )

    # OCF to Sales Ratio
    metric.ocf_to_sales = calculate_ratio(
      statement.operating_cash_flow,
      statement.net_sales
    )

    # Free Cash Flow = Operating Cash Flow + Investing Cash Flow
    if statement.operating_cash_flow && statement.investing_cash_flow
      metric.free_cash_flow = statement.operating_cash_flow + statement.investing_cash_flow
    end

    # OCF - ICF Gap (positive is good, means OCF > abs(ICF))
    if statement.operating_cash_flow && statement.investing_cash_flow
      metric.ocf_icf_gap = statement.operating_cash_flow + statement.investing_cash_flow
    end

    metric.save!
    metric
  end

  # Calculate valuation metrics based on stock price
  def calculate_valuation_metrics(date:)
    stock_price = @company.stock_prices.find_by(date: date)
    return unless stock_price

    # Find the most recent financial statement before this date
    statement = @company.financial_statements
                        .where("filed_date <= ?", date)
                        .order(filed_date: :desc)
                        .first
    return unless statement

    metric = ValuationMetric.find_or_initialize_by(
      company: @company,
      date: date
    )

    # Calculate market cap
    if stock_price.close_price && statement.shares_outstanding
      metric.market_cap = stock_price.close_price * statement.shares_outstanding
    end

    # PER = Market Cap / Net Income (or Price / EPS)
    metric.per = calculate_ratio(metric.market_cap, statement.net_income)

    # PBR = Market Cap / Total Equity
    metric.pbr = calculate_ratio(metric.market_cap, statement.total_equity)

    # PSR = Market Cap / Net Sales
    metric.psr = calculate_ratio(metric.market_cap, statement.net_sales)

    # PCFR = Market Cap / Operating Cash Flow
    metric.pcfr = calculate_ratio(metric.market_cap, statement.operating_cash_flow)

    metric.save!
    metric
  end

  private

  # Calculate ratio, handling nil and zero values
  def calculate_ratio(numerator, denominator)
    return nil if numerator.nil? || denominator.nil?
    return nil if denominator.zero?

    (numerator.to_f / denominator.to_f * 100).round(4)
  end

  # Calculate growth rate (YoY percentage)
  def calculate_growth_rate(previous_value, current_value)
    return nil if previous_value.nil? || current_value.nil?
    return nil if previous_value.zero?

    ((current_value.to_f - previous_value.to_f) / previous_value.to_f * 100).round(4)
  end

  # Find previous year's statement for growth calculations
  def find_previous_statement(statement)
    @company.financial_statements
            .where(fiscal_period: statement.fiscal_period)
            .where("fiscal_year < ?", statement.fiscal_year)
            .order(fiscal_year: :desc)
            .first
  end
end
