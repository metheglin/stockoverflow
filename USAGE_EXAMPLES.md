# Stock Overflow - Usage Examples

This document provides practical examples of how to use the Stock Overflow system for analyzing Japanese listed companies.

## Table of Contents

1. [Data Import](#data-import)
2. [Basic Queries](#basic-queries)
3. [Use Case Examples](#use-case-examples)
4. [Advanced Analysis](#advanced-analysis)

## Data Import

### Import All Data (Initial Setup)

```bash
# Import companies, financial statements, and stock prices for the last year
bundle exec rake stock_data:refresh_all

# Or with custom date range
bundle exec rake stock_data:refresh_all[2023-01-01,2024-12-31]
```

### Import Companies Only

```bash
bundle exec rake stock_data:import_companies
```

### Import Financial Statements

```bash
# Import all statements
bundle exec rake stock_data:import_statements

# Import for specific company
bundle exec rake stock_data:import_statements[7203]

# Import for specific date
bundle exec rake stock_data:import_statements[,2024-03-31]
```

### Import Stock Prices

```bash
# Import last year's prices
bundle exec rake stock_data:import_prices

# Import for specific date range
bundle exec rake stock_data:import_prices[2024-01-01,2024-12-31]

# Import for specific company
bundle exec rake stock_data:import_prices[2024-01-01,2024-12-31,7203]
```

### Calculate Metrics

```bash
# Calculate all metrics
bundle exec rake stock_data:calculate_metrics

# Calculate valuation metrics for specific date
bundle exec rake stock_data:calculate_valuations[2024-12-31]
```

## Basic Queries

### Rails Console Examples

```ruby
# Start Rails console
bundle exec rails console

# Get a company by code
company = Company.find_by(code: "7203")

# Get latest financial statement
company.latest_financial_statement

# Get latest stock price
company.latest_stock_price

# Get recent growth trends
company.growth_trend(periods: 4)

# Get profitability trends
company.profitability_trend(periods: 4)

# Get metrics summary
company.metrics_summary
```

## Use Case Examples

### Use Case 1: Find Companies with 6 Consecutive Periods of Revenue/Profit Growth

#### Using Rake Task

```bash
# Find companies with 6 consecutive periods of revenue growth
bundle exec rake analysis:consecutive_growth[6]
```

#### Using Rails Console

```ruby
# Find companies with consecutive revenue growth
companies = Company.with_consecutive_revenue_growth(6)

companies.each do |company|
  puts "#{company.code} - #{company.name}"
  puts "Average Revenue Growth: #{company.avg_revenue_growth}%"
  puts ""
end

# Find companies with both revenue and profit growth
analyzer = CompanyAnalyzer.find_consecutive_growth_companies(
  revenue_periods: 6,
  profit_periods: 6
)

analyzer.each do |company|
  puts "#{company.code} - #{company.name}"
  # Show detailed metrics...
end
```

#### Using Model Methods

```ruby
# Check if a specific company has consecutive growth
company = Company.find_by(code: "7203")
company.consecutive_revenue_growth?(periods: 6)  # => true/false
company.consecutive_profit_growth?(periods: 6)   # => true/false
```

### Use Case 2: Find Companies with Positive OCF and Negative ICF

#### Using Rake Task

```bash
bundle exec rake analysis:ocf_icf_gap
```

#### Using Rails Console

```ruby
# Find companies with positive OCF, negative ICF
companies = Company.with_positive_ocf_negative_icf
                   .with_positive_ocf_icf_gap

companies.each do |company|
  latest_cf = company.cash_flow_metrics.order(fiscal_year: :desc).first
  statement = company.financial_statements.find_by(
    fiscal_year: latest_cf.fiscal_year,
    fiscal_period: latest_cf.fiscal_period
  )

  puts "#{company.code} - #{company.name}"
  puts "OCF: #{statement.operating_cash_flow}"
  puts "ICF: #{statement.investing_cash_flow}"
  puts "Gap: #{latest_cf.ocf_icf_gap}"
  puts ""
end

# Find companies where gap recently turned positive
turnaround_companies = CompanyAnalyzer.find_gap_turnaround_companies(periods: 4)
```

### Use Case 3: Analyze Historical Metrics Before Breakthrough

#### Using Rake Task

```bash
# Analyze Toyota (7203)
bundle exec rake analysis:historical_metrics[7203]
```

#### Using Rails Console

```ruby
company = Company.find_by(code: "7203")

# Get breakthrough analysis
analysis = CompanyAnalyzer.analyze_breakthrough_precursors(
  company,
  breakthrough_year: 2024,
  breakthrough_period: "Q4",
  lookback_periods: 8
)

puts "Company: #{analysis[:company][:name]}"
puts "Breakthrough: #{analysis[:breakthrough_period]}"
puts ""
puts "Patterns identified:"
analysis[:patterns].each { |p| puts "  - #{p}" }
puts ""
puts "Profitability History:"
analysis[:profitability_history].each do |period|
  puts "  #{period[:period]}: ROE=#{period[:roe]}%, ROA=#{period[:roa]}%"
end
```

## Advanced Analysis

### Compare Multiple Companies

```ruby
# Compare profitability of multiple companies
companies = Company.where(code: ["7203", "6758", "9984"])
comparison = CompanyAnalyzer.compare_companies(companies, metric_type: :profitability)

comparison.each do |data|
  puts "#{data[:company].code} - #{data[:company].name}"
  puts "  ROE: #{data[:roe]}%"
  puts "  ROA: #{data[:roa]}%"
  puts "  Operating Margin: #{data[:operating_margin]}%"
  puts ""
end
```

### Find Similar Companies

```ruby
# Find companies similar to Toyota
company = Company.find_by(code: "7203")
similar = CompanyAnalyzer.find_similar_companies(company, tolerance: 20.0)

similar.each do |similar_company|
  puts "#{similar_company.code} - #{similar_company.name}"
end
```

### Filter by Industry and Metrics

```ruby
# Find high ROE companies in automotive industry
companies = Company.by_industry("自動車・輸送機")
                   .high_roe(15)
                   .includes(:profitability_metrics)

companies.each do |company|
  latest = company.profitability_metrics.order(fiscal_year: :desc).first
  puts "#{company.code} - #{company.name}: ROE #{latest.roe}%"
end
```

### Custom Queries

```ruby
# Companies with improving margins
companies = Company.joins(:profitability_metrics)
                   .select("companies.*,
                           AVG(profitability_metrics.operating_margin) as avg_margin")
                   .group("companies.id")
                   .having("avg_margin > 10")
                   .order("avg_margin DESC")

# Companies with strong free cash flow
companies = Company.joins(:cash_flow_metrics)
                   .where("cash_flow_metrics.free_cash_flow > 1000000000")
                   .distinct

# Companies by market cap (requires valuation metrics)
companies = Company.joins(:valuation_metrics)
                   .select("companies.*,
                           MAX(valuation_metrics.market_cap) as max_market_cap")
                   .group("companies.id")
                   .order("max_market_cap DESC")
                   .limit(100)
```

## Database Summary

```bash
# Show database statistics
bundle exec rake analysis:summary
```

## Scheduled Updates

For production use, you may want to schedule regular data updates:

```ruby
# Create a scheduled job (using whenever, sidekiq-cron, or similar)
# In config/schedule.rb (if using whenever gem):

# Daily at 1 AM - Import latest financial statements
every 1.day, at: '1:00 am' do
  runner "ImportFinancialStatementsJob.perform_now"
end

# Daily at 2 AM - Import yesterday's stock prices
every 1.day, at: '2:00 am' do
  yesterday = Date.yesterday.strftime("%Y-%m-%d")
  runner "ImportStockPricesJob.perform_now(from: '#{yesterday}', to: '#{yesterday}')"
end

# Daily at 3 AM - Calculate metrics
every 1.day, at: '3:00 am' do
  runner "FinancialStatement.where('updated_at > ?', 1.day.ago).find_each do |s|
    CalculateMetricsJob.perform_later(
      company_id: s.company_id,
      fiscal_year: s.fiscal_year,
      fiscal_period: s.fiscal_period
    )
  end"
end
```

## Tips and Best Practices

1. **Start Small**: Import data for a few companies first to test the workflow
2. **Regular Updates**: Set up scheduled jobs to keep data fresh
3. **Index Performance**: Monitor query performance and add indexes as needed
4. **Data Validation**: Always check imported data for completeness
5. **Backup**: Regularly backup your SQLite database
6. **API Rate Limits**: Be mindful of API rate limits when importing large datasets

## Troubleshooting

### API Authentication Errors

If you encounter authentication errors with JQUANTS:

```ruby
# Test the client directly
client = JquantsClient.new
client.listed_companies
```

### Missing Data

If metrics are not calculated:

```ruby
# Manually calculate for a company
company = Company.find_by(code: "7203")
statement = company.financial_statements.last

calculator = MetricCalculator.new(company)
calculator.calculate_all_metrics(
  fiscal_year: statement.fiscal_year,
  fiscal_period: statement.fiscal_period
)
```

### Performance Issues

For large datasets, use batch processing:

```ruby
# Process in batches
Company.find_in_batches(batch_size: 100) do |batch|
  batch.each do |company|
    # Process company...
  end
end
```
