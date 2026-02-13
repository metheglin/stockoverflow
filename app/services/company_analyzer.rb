# Service for analyzing company financial data and identifying investment opportunities
class CompanyAnalyzer
  # Find companies with consecutive periods of revenue and profit growth
  # @param revenue_periods [Integer] Number of consecutive revenue growth periods required
  # @param profit_periods [Integer] Number of consecutive profit growth periods required
  # @return [ActiveRecord::Relation] Companies matching the criteria
  def self.find_consecutive_growth_companies(revenue_periods: 6, profit_periods: 6)
    revenue_companies = Company.with_consecutive_revenue_growth(revenue_periods).pluck(:id)
    profit_companies = Company.with_consecutive_profit_growth(profit_periods).pluck(:id)

    Company.where(id: revenue_companies & profit_companies)
           .includes(:growth_metrics, :profitability_metrics)
  end

  # Find companies with positive OCF, negative ICF, and positive gap
  # @return [ActiveRecord::Relation] Companies matching the criteria
  def self.find_cash_flow_positive_companies
    Company.with_positive_ocf_negative_icf
           .with_positive_ocf_icf_gap
           .includes(:cash_flow_metrics, :financial_statements)
  end

  # Find companies where OCF-ICF gap recently turned positive
  # @param periods [Integer] Number of recent periods to check
  # @return [Array<Company>] Companies with recent gap improvement
  def self.find_gap_turnaround_companies(periods: 4)
    companies = []

    Company.with_positive_ocf_icf_gap.find_each do |company|
      recent_metrics = company.cash_flow_metrics
                              .order(fiscal_year: :desc, fiscal_period: :desc)
                              .limit(periods)
                              .to_a
                              .reverse

      # Check if gap turned from negative to positive
      if recent_metrics.size >= 2
        previous_negative = recent_metrics[0..-2].any? { |m| m.ocf_icf_gap.to_f <= 0 }
        current_positive = recent_metrics.last.ocf_icf_gap.to_f > 0

        companies << company if previous_negative && current_positive
      end
    end

    companies
  end

  # Analyze a company's historical metrics before a breakthrough period
  # @param company [Company] The company to analyze
  # @param breakthrough_year [Integer] The fiscal year of the breakthrough
  # @param breakthrough_period [String] The fiscal period of the breakthrough
  # @param lookback_periods [Integer] Number of periods to look back
  # @return [Hash] Analysis results
  def self.analyze_breakthrough_precursors(company, breakthrough_year:, breakthrough_period:, lookback_periods: 8)
    # Find all statements before the breakthrough
    statements = company.financial_statements
                        .where("fiscal_year < ? OR (fiscal_year = ? AND fiscal_period < ?)",
                              breakthrough_year, breakthrough_year, breakthrough_period)
                        .order(fiscal_year: :desc, fiscal_period: :desc)
                        .limit(lookback_periods)
                        .to_a
                        .reverse

    return {} if statements.empty?

    # Collect historical metrics
    profitability_history = statements.map do |stmt|
      metric = company.profitability_metrics.find_by(
        fiscal_year: stmt.fiscal_year,
        fiscal_period: stmt.fiscal_period
      )
      {
        period: "#{stmt.fiscal_year}/#{stmt.fiscal_period}",
        roe: metric&.roe,
        roa: metric&.roa,
        operating_margin: metric&.operating_margin,
        net_margin: metric&.net_margin
      }
    end

    growth_history = statements.map do |stmt|
      metric = company.growth_metrics.find_by(
        fiscal_year: stmt.fiscal_year,
        fiscal_period: stmt.fiscal_period
      )
      {
        period: "#{stmt.fiscal_year}/#{stmt.fiscal_period}",
        revenue_growth: metric&.revenue_growth_rate,
        operating_income_growth: metric&.operating_income_growth_rate,
        net_income_growth: metric&.net_income_growth_rate
      }
    end

    cash_flow_history = statements.map do |stmt|
      metric = company.cash_flow_metrics.find_by(
        fiscal_year: stmt.fiscal_year,
        fiscal_period: stmt.fiscal_period
      )
      {
        period: "#{stmt.fiscal_year}/#{stmt.fiscal_period}",
        ocf_to_sales: metric&.ocf_to_sales,
        free_cash_flow: metric&.free_cash_flow,
        ocf_icf_gap: metric&.ocf_icf_gap
      }
    end

    # Identify trends and patterns
    patterns = identify_patterns(profitability_history, growth_history, cash_flow_history)

    {
      company: {
        code: company.code,
        name: company.name,
        industry: company.industry
      },
      breakthrough_period: "#{breakthrough_year}/#{breakthrough_period}",
      profitability_history: profitability_history,
      growth_history: growth_history,
      cash_flow_history: cash_flow_history,
      patterns: patterns
    }
  end

  # Compare companies by specific metrics
  # @param companies [Array<Company>] Companies to compare
  # @param metric_type [Symbol] Type of metric (:profitability, :growth, :cash_flow)
  # @return [Array<Hash>] Comparison data
  def self.compare_companies(companies, metric_type: :profitability)
    companies.map do |company|
      latest_statement = company.latest_financial_statement
      next unless latest_statement

      case metric_type
      when :profitability
        metric = company.profitability_metrics.find_by(
          fiscal_year: latest_statement.fiscal_year,
          fiscal_period: latest_statement.fiscal_period
        )
        {
          company: company,
          roe: metric&.roe,
          roa: metric&.roa,
          operating_margin: metric&.operating_margin,
          net_margin: metric&.net_margin
        }
      when :growth
        metric = company.growth_metrics.find_by(
          fiscal_year: latest_statement.fiscal_year,
          fiscal_period: latest_statement.fiscal_period
        )
        {
          company: company,
          revenue_growth: metric&.revenue_growth_rate,
          operating_income_growth: metric&.operating_income_growth_rate,
          net_income_growth: metric&.net_income_growth_rate
        }
      when :cash_flow
        metric = company.cash_flow_metrics.find_by(
          fiscal_year: latest_statement.fiscal_year,
          fiscal_period: latest_statement.fiscal_period
        )
        {
          company: company,
          ocf_to_sales: metric&.ocf_to_sales,
          free_cash_flow: metric&.free_cash_flow,
          ocf_icf_gap: metric&.ocf_icf_gap
        }
      end
    end.compact
  end

  # Find companies similar to a given company based on metrics
  # @param company [Company] Reference company
  # @param tolerance [Float] Tolerance percentage for similarity (default 20%)
  # @return [Array<Company>] Similar companies
  def self.find_similar_companies(company, tolerance: 20.0)
    latest = company.latest_financial_statement
    return [] unless latest

    prof_metric = company.profitability_metrics.find_by(
      fiscal_year: latest.fiscal_year,
      fiscal_period: latest.fiscal_period
    )
    return [] unless prof_metric

    # Find companies with similar ROE and ROA
    roe_range = calculate_range(prof_metric.roe, tolerance)
    roa_range = calculate_range(prof_metric.roa, tolerance)

    Company.joins(:profitability_metrics)
           .where.not(id: company.id)
           .where(industry: company.industry)
           .where("profitability_metrics.roe BETWEEN ? AND ?", roe_range[0], roe_range[1])
           .where("profitability_metrics.roa BETWEEN ? AND ?", roa_range[0], roa_range[1])
           .distinct
  end

  private

  # Identify patterns in historical data
  def self.identify_patterns(profitability, growth, cash_flow)
    patterns = []

    # Check for improving profitability trend
    roe_values = profitability.map { |p| p[:roe] }.compact
    if roe_values.size >= 3 && consistently_increasing?(roe_values.last(3))
      patterns << "Improving ROE trend"
    end

    # Check for consistent revenue growth
    revenue_growth = growth.map { |g| g[:revenue_growth] }.compact
    if revenue_growth.size >= 3 && revenue_growth.last(3).all? { |v| v > 0 }
      patterns << "Consistent revenue growth"
    end

    # Check for improving cash flow
    ocf_gaps = cash_flow.map { |cf| cf[:ocf_icf_gap] }.compact
    if ocf_gaps.size >= 2 && ocf_gaps.last > ocf_gaps.first
      patterns << "Improving OCF-ICF gap"
    end

    patterns
  end

  # Check if values are consistently increasing
  def self.consistently_increasing?(values)
    return false if values.size < 2

    values.each_cons(2).all? { |a, b| b > a }
  end

  # Calculate range for similarity matching
  def self.calculate_range(value, tolerance)
    return [nil, nil] if value.nil?

    margin = value * (tolerance / 100.0)
    [value - margin, value + margin]
  end
end
