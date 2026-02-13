namespace :analysis do
  desc "Find companies with N consecutive periods of revenue/profit growth"
  task :consecutive_growth, [:periods] => :environment do |t, args|
    periods = (args[:periods] || 6).to_i

    puts "Finding companies with #{periods} consecutive periods of revenue growth..."
    puts "=" * 80

    companies = Company.joins(:growth_metrics)
                       .group("companies.id")
                       .having("COUNT(CASE WHEN growth_metrics.revenue_growth_rate > 0 THEN 1 END) >= ?", periods)
                       .select("companies.*, AVG(growth_metrics.revenue_growth_rate) as avg_revenue_growth")
                       .order("avg_revenue_growth DESC")

    companies.each do |company|
      growth_records = company.growth_metrics
                              .where("revenue_growth_rate > 0")
                              .order(fiscal_year: :desc, fiscal_period: :desc)
                              .limit(periods)

      puts "\n#{company.code} - #{company.name}"
      puts "Average Revenue Growth: #{company.avg_revenue_growth&.round(2)}%"
      puts "Recent growth periods:"

      growth_records.each do |metric|
        puts "  #{metric.fiscal_year}/#{metric.fiscal_period}: " +
             "Revenue: #{metric.revenue_growth_rate&.round(2)}%, " +
             "Operating Income: #{metric.operating_income_growth_rate&.round(2)}%, " +
             "Net Income: #{metric.net_income_growth_rate&.round(2)}%"
      end
    end

    puts "\n" + "=" * 80
    puts "Total companies found: #{companies.count}"
  end

  desc "Find companies with positive OCF and negative ICF gap turning positive"
  task ocf_icf_gap: :environment do
    puts "Finding companies with OCF+ and ICF- where gap turned positive..."
    puts "=" * 80

    companies = Company.joins(:cash_flow_metrics, :financial_statements)
                       .where("financial_statements.operating_cash_flow > 0")
                       .where("financial_statements.investing_cash_flow < 0")
                       .where("cash_flow_metrics.ocf_icf_gap > 0")
                       .distinct
                       .order("cash_flow_metrics.ocf_icf_gap DESC")

    companies.each do |company|
      latest_cf_metric = company.cash_flow_metrics
                                .joins(:company)
                                .where("ocf_icf_gap > 0")
                                .order(fiscal_year: :desc, fiscal_period: :desc)
                                .first

      next unless latest_cf_metric

      statement = company.financial_statements
                         .find_by(fiscal_year: latest_cf_metric.fiscal_year,
                                 fiscal_period: latest_cf_metric.fiscal_period)

      puts "\n#{company.code} - #{company.name}"
      puts "Latest Period: #{latest_cf_metric.fiscal_year}/#{latest_cf_metric.fiscal_period}"
      puts "Operating Cash Flow: #{format_number(statement&.operating_cash_flow)}"
      puts "Investing Cash Flow: #{format_number(statement&.investing_cash_flow)}"
      puts "OCF-ICF Gap: #{format_number(latest_cf_metric.ocf_icf_gap)}"
      puts "Free Cash Flow: #{format_number(latest_cf_metric.free_cash_flow)}"
    end

    puts "\n" + "=" * 80
    puts "Total companies found: #{companies.count}"
  end

  desc "Analyze historical metrics before breakthrough for a specific company"
  task :historical_metrics, [:code] => :environment do |t, args|
    code = args[:code]
    unless code
      puts "Please provide a company code: rake analysis:historical_metrics[7203]"
      exit
    end

    company = Company.find_by(code: code)
    unless company
      puts "Company with code #{code} not found"
      exit
    end

    puts "Historical Metrics Analysis for #{company.code} - #{company.name}"
    puts "=" * 80

    # Profitability Metrics
    puts "\n--- Profitability Metrics ---"
    puts sprintf("%-10s %-8s %10s %10s %10s %10s", "Year", "Period", "ROE(%)", "ROA(%)", "Op.Margin(%)", "Net Margin(%)")
    puts "-" * 80

    company.profitability_metrics.order(:fiscal_year, :fiscal_period).each do |metric|
      puts sprintf("%-10s %-8s %10.2f %10.2f %10.2f %10.2f",
                  metric.fiscal_year,
                  metric.fiscal_period,
                  metric.roe || 0,
                  metric.roa || 0,
                  metric.operating_margin || 0,
                  metric.net_margin || 0)
    end

    # Growth Metrics
    puts "\n--- Growth Metrics ---"
    puts sprintf("%-10s %-8s %12s %12s %12s", "Year", "Period", "Revenue(%)", "Op.Income(%)", "Net Income(%)")
    puts "-" * 80

    company.growth_metrics.order(:fiscal_year, :fiscal_period).each do |metric|
      puts sprintf("%-10s %-8s %12.2f %12.2f %12.2f",
                  metric.fiscal_year,
                  metric.fiscal_period,
                  metric.revenue_growth_rate || 0,
                  metric.operating_income_growth_rate || 0,
                  metric.net_income_growth_rate || 0)
    end

    # Cash Flow Metrics
    puts "\n--- Cash Flow Metrics ---"
    puts sprintf("%-10s %-8s %15s %15s %15s", "Year", "Period", "OCF/Sales(%)", "Free CF", "OCF-ICF Gap")
    puts "-" * 80

    company.cash_flow_metrics.order(:fiscal_year, :fiscal_period).each do |metric|
      puts sprintf("%-10s %-8s %15.2f %15s %15s",
                  metric.fiscal_year,
                  metric.fiscal_period,
                  metric.ocf_to_sales || 0,
                  format_number(metric.free_cash_flow),
                  format_number(metric.ocf_icf_gap))
    end

    # Financial Statements Summary
    puts "\n--- Financial Statements Summary ---"
    puts sprintf("%-10s %-8s %15s %15s %15s", "Year", "Period", "Net Sales", "Op. Income", "Net Income")
    puts "-" * 80

    company.financial_statements.order(:fiscal_year, :fiscal_period).each do |statement|
      puts sprintf("%-10s %-8s %15s %15s %15s",
                  statement.fiscal_year,
                  statement.fiscal_period,
                  format_number(statement.net_sales),
                  format_number(statement.operating_income),
                  format_number(statement.net_income))
    end

    puts "\n" + "=" * 80
  end

  desc "Show summary statistics for all companies"
  task summary: :environment do
    puts "Stock Overflow - Database Summary"
    puts "=" * 80

    puts "\nMaster Data:"
    puts "  Companies: #{Company.count}"
    puts "  Financial Statements: #{FinancialStatement.count}"
    puts "  Stock Prices: #{StockPrice.count}"

    puts "\nAnalytical Metrics:"
    puts "  Growth Metrics: #{GrowthMetric.count}"
    puts "  Profitability Metrics: #{ProfitabilityMetric.count}"
    puts "  Valuation Metrics: #{ValuationMetric.count}"
    puts "  Cash Flow Metrics: #{CashFlowMetric.count}"

    if FinancialStatement.any?
      puts "\nData Coverage:"
      puts "  Earliest fiscal year: #{FinancialStatement.minimum(:fiscal_year)}"
      puts "  Latest fiscal year: #{FinancialStatement.maximum(:fiscal_year)}"
    end

    if StockPrice.any?
      puts "  Earliest price date: #{StockPrice.minimum(:date)}"
      puts "  Latest price date: #{StockPrice.maximum(:date)}"
    end

    puts "\n" + "=" * 80
  end

  private

  def format_number(num)
    return "N/A" if num.nil?
    num.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end
end
