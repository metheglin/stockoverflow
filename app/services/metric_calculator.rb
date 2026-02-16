class MetricCalculator
  def initialize(company)
    @company = company
  end

  def calculate_all
    calculate_profitability_metrics
    calculate_growth_metrics
    calculate_cash_flow_metrics
    calculate_valuation_metrics
  end

  def calculate_profitability_metrics
    @company.financial_statements.find_each do |fs|
      metric = ProfitabilityMetric.find_or_initialize_by(
        company: @company,
        fiscal_year: fs.fiscal_year,
        fiscal_period: fs.fiscal_period
      )

      metric.assign_attributes(
        roe: safe_divide(fs.net_income, fs.total_equity),
        roa: safe_divide(fs.net_income, fs.total_assets),
        operating_margin: safe_divide(fs.operating_income, fs.net_sales),
        net_margin: safe_divide(fs.net_income, fs.net_sales)
      )

      metric.save! if metric.changed?
    end
  end

  def calculate_growth_metrics
    statements = @company.financial_statements.ordered.to_a

    statements.each do |current|
      # Find the same period from the previous fiscal year
      previous = statements.find do |s|
        s.fiscal_year == current.fiscal_year - 1 && s.fiscal_period == current.fiscal_period
      end
      next unless previous

      metric = GrowthMetric.find_or_initialize_by(
        company: @company,
        fiscal_year: current.fiscal_year,
        fiscal_period: current.fiscal_period
      )

      current_eps = current.eps
      previous_eps = previous.eps

      metric.assign_attributes(
        revenue_growth_rate: growth_rate(previous.net_sales, current.net_sales),
        operating_income_growth_rate: growth_rate(previous.operating_income, current.operating_income),
        net_income_growth_rate: growth_rate(previous.net_income, current.net_income),
        eps_growth_rate: growth_rate(previous_eps, current_eps),
        total_assets_growth_rate: growth_rate(previous.total_assets, current.total_assets)
      )

      metric.save! if metric.changed?
    end
  end

  def calculate_cash_flow_metrics
    @company.financial_statements.find_each do |fs|
      metric = CashFlowMetric.find_or_initialize_by(
        company: @company,
        fiscal_year: fs.fiscal_year,
        fiscal_period: fs.fiscal_period
      )

      free_cash_flow = if fs.operating_cash_flow && fs.investing_cash_flow
        fs.operating_cash_flow + fs.investing_cash_flow
      end

      metric.assign_attributes(
        free_cash_flow: free_cash_flow,
        ocf_to_sales: safe_divide(fs.operating_cash_flow, fs.net_sales),
        ocf_icf_gap: free_cash_flow
      )

      metric.save! if metric.changed?
    end
  end

  def calculate_valuation_metrics
    # Get latest financial statement for valuation calculations
    latest_fs = @company.financial_statements.annual.order(fiscal_year: :desc).first
    return unless latest_fs

    @company.stock_prices.find_each do |sp|
      next unless sp.close_price && sp.close_price > 0

      metric = ValuationMetric.find_or_initialize_by(
        company: @company,
        date: sp.date
      )

      shares = latest_fs.shares_outstanding
      market_cap = shares && shares > 0 ? sp.close_price * shares : nil

      eps = latest_fs.eps
      bps = if latest_fs.total_equity && shares && shares > 0
        latest_fs.total_equity / shares.to_d
      end
      sales_per_share = if latest_fs.net_sales && shares && shares > 0
        latest_fs.net_sales / shares.to_d
      end
      cfps = if latest_fs.operating_cash_flow && shares && shares > 0
        latest_fs.operating_cash_flow / shares.to_d
      end

      metric.assign_attributes(
        per: safe_divide(sp.close_price, eps),
        pbr: safe_divide(sp.close_price, bps),
        psr: safe_divide(sp.close_price, sales_per_share),
        pcfr: safe_divide(sp.close_price, cfps),
        market_cap: market_cap
      )

      metric.save! if metric.changed?
    end
  end

  private

  def safe_divide(numerator, denominator)
    return nil if numerator.nil? || denominator.nil? || denominator.zero?
    (numerator.to_d / denominator.to_d).round(4)
  end

  def growth_rate(previous_value, current_value)
    return nil if previous_value.nil? || current_value.nil? || previous_value.zero?
    ((current_value - previous_value).to_d / previous_value.to_d).round(4)
  end
end
