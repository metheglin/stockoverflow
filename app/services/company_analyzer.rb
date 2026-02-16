class CompanyAnalyzer
  # Find companies with N consecutive periods of revenue/profit growth
  # Returns companies sorted by average growth rate (descending)
  def self.consecutive_growth(periods: 6, metric: :revenue_growth_rate, period_type: "FY")
    results = []

    Company.find_each do |company|
      growth_records = company.growth_metrics
        .where(fiscal_period: period_type)
        .order(fiscal_year: :asc)
        .pluck(:fiscal_year, metric)

      # Find longest consecutive streak of positive growth
      consecutive = find_consecutive_positive(growth_records)

      if consecutive[:count] >= periods
        results << {
          company: company,
          consecutive_periods: consecutive[:count],
          average_growth: consecutive[:average],
          years: consecutive[:years]
        }
      end
    end

    results.sort_by { |r| -r[:average_growth] }
  end

  # Find companies where OCF is positive, ICF is negative, and OCF+ICF gap has turned positive
  # This pattern indicates a company generating more cash than it invests
  def self.cash_flow_turnaround(period_type: "FY")
    results = []

    Company.find_each do |company|
      cf_records = company.cash_flow_metrics
        .where(fiscal_period: period_type)
        .order(fiscal_year: :asc)
        .to_a

      next if cf_records.size < 2

      # Find companies where the gap turned from negative to positive
      turnaround = detect_cash_flow_turnaround(company, cf_records)
      results << turnaround if turnaround
    end

    results.sort_by { |r| -(r[:latest_fcf] || 0) }
  end

  # Analyze historical metrics for a specific company to find pre-breakthrough patterns
  def self.company_profile(company)
    {
      company: {
        code: company.code,
        name: company.name,
        market: company.market,
        industry: company.industry,
        sector: company.sector
      },
      financials: company.financial_statements.annual.ordered.map do |fs|
        {
          fiscal_year: fs.fiscal_year,
          net_sales: fs.net_sales,
          operating_income: fs.operating_income,
          net_income: fs.net_income,
          total_assets: fs.total_assets,
          total_equity: fs.total_equity,
          eps: fs.eps
        }
      end,
      profitability: company.profitability_metrics.annual.ordered.map do |pm|
        {
          fiscal_year: pm.fiscal_year,
          roe: pm.roe,
          roa: pm.roa,
          operating_margin: pm.operating_margin,
          net_margin: pm.net_margin
        }
      end,
      growth: company.growth_metrics.annual.ordered.map do |gm|
        {
          fiscal_year: gm.fiscal_year,
          revenue_growth: gm.revenue_growth_rate,
          operating_income_growth: gm.operating_income_growth_rate,
          net_income_growth: gm.net_income_growth_rate,
          eps_growth: gm.eps_growth_rate
        }
      end,
      cash_flow: company.cash_flow_metrics.annual.ordered.map do |cfm|
        {
          fiscal_year: cfm.fiscal_year,
          free_cash_flow: cfm.free_cash_flow,
          ocf_to_sales: cfm.ocf_to_sales
        }
      end
    }
  end

  private_class_method def self.find_consecutive_positive(records)
    best = { count: 0, average: 0, years: [] }
    current = { count: 0, total: 0, years: [] }

    records.each do |year, value|
      if value && value > 0
        current[:count] += 1
        current[:total] += value
        current[:years] << year
      else
        if current[:count] > best[:count]
          best = {
            count: current[:count],
            average: current[:count] > 0 ? current[:total] / current[:count] : 0,
            years: current[:years].dup
          }
        end
        current = { count: 0, total: 0, years: [] }
      end
    end

    # Check final streak
    if current[:count] > best[:count]
      best = {
        count: current[:count],
        average: current[:count] > 0 ? current[:total] / current[:count] : 0,
        years: current[:years].dup
      }
    end

    best
  end

  private_class_method def self.detect_cash_flow_turnaround(company, cf_records)
    # Look for transition from negative to positive FCF
    turnaround_year = nil
    cf_records.each_cons(2) do |prev, curr|
      if prev.free_cash_flow && curr.free_cash_flow &&
         prev.free_cash_flow < 0 && curr.free_cash_flow > 0
        turnaround_year = curr.fiscal_year
      end
    end

    return nil unless turnaround_year

    latest = cf_records.last
    # Also check that latest OCF is positive
    latest_fs = company.financial_statements
      .where(fiscal_year: latest.fiscal_year, fiscal_period: latest.fiscal_period)
      .first
    return nil unless latest_fs&.operating_cash_flow && latest_fs.operating_cash_flow > 0

    {
      company: company,
      turnaround_year: turnaround_year,
      latest_fcf: latest.free_cash_flow,
      latest_ocf_to_sales: latest.ocf_to_sales,
      cash_flow_history: cf_records.map do |cfm|
        { fiscal_year: cfm.fiscal_year, fcf: cfm.free_cash_flow, ocf_to_sales: cfm.ocf_to_sales }
      end
    }
  end
end
