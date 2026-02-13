# Stock Overflow - Japanese Stock Market Analysis System

A Rails application for analyzing Japanese listed companies using EDINET and JQUANTS APIs. This system collects financial statements, stock prices, and calculates various analytical metrics to identify investment opportunities.

## Requirements

- Ruby 4.0.1+
- Rails 8.1.2+
- SQLite3

## Setup

1. Install dependencies:
```bash
bundle install
```

2. Create and migrate the database:
```bash
bin/rails db:create
bin/rails db:migrate
```

3. Configure API keys in `.env`:
```
EDINET_API_KEY=your_edinet_api_key
JQUANTS_API_KEY=your_jquants_api_key
```

## Database Schema

The system uses a hierarchical data structure:

### Master Data Tables
- **companies**: Listed company information (code, name, market, industry)
- **financial_statements**: Quarterly/annual financial reports (P/L, B/S, C/F)
- **stock_prices**: Daily stock price data (OHLC, volume)

### Analytical Metrics Tables
- **growth_metrics**: YoY growth rates (revenue, operating income, net income, assets)
- **profitability_metrics**: ROE, ROA, operating margin, net margin
- **valuation_metrics**: PER, PBR, PSR, PCFR, market cap, dividend yield
- **cash_flow_metrics**: OCF to sales ratio, free cash flow, OCF-ICF gap

## Data Import

### Import Listed Companies
```ruby
ImportCompaniesJob.perform_now
```

### Import Financial Statements
```ruby
# Import all available statements
ImportFinancialStatementsJob.perform_now

# Import for specific company
ImportFinancialStatementsJob.perform_now(code: "7203")

# Import for specific date
ImportFinancialStatementsJob.perform_now(date: "2024-03-31")
```

### Import Stock Prices
```ruby
# Import price data for a date range
ImportStockPricesJob.perform_now(
  from: "2024-01-01",
  to: "2024-12-31"
)

# Import for specific company
ImportStockPricesJob.perform_now(
  from: "2024-01-01",
  to: "2024-12-31",
  code: "7203"
)
```

### Calculate Metrics
```ruby
# Calculate metrics for a specific company and period
company = Company.find_by(code: "7203")
calculator = MetricCalculator.new(company)
calculator.calculate_all_metrics(fiscal_year: 2024, fiscal_period: "Q4")

# Calculate metrics for all companies
CalculateMetricsJob.calculate_all
```

## Quick Start

### 1. Import Data

```bash
# Import all data (companies, statements, and prices)
bundle exec rake stock_data:refresh_all

# Or import step by step
bundle exec rake stock_data:import_companies
bundle exec rake stock_data:import_statements
bundle exec rake stock_data:import_prices[2024-01-01,2024-12-31]
bundle exec rake stock_data:calculate_metrics
```

### 2. Run Analysis

```bash
# Find companies with 6 consecutive periods of growth
bundle exec rake analysis:consecutive_growth[6]

# Find companies with positive OCF-ICF gap
bundle exec rake analysis:ocf_icf_gap

# Analyze specific company
bundle exec rake analysis:historical_metrics[7203]

# Show database summary
bundle exec rake analysis:summary
```

## Use Cases

### Use Case 1: Find Companies with Consecutive Revenue/Profit Growth

```bash
# Using rake task
bundle exec rake analysis:consecutive_growth[6]
```

```ruby
# Using model scopes
companies = Company.with_consecutive_revenue_growth(6)

# Using analyzer service
companies = CompanyAnalyzer.find_consecutive_growth_companies(
  revenue_periods: 6,
  profit_periods: 6
)
```

### Use Case 2: Find Companies with Positive OCF and Negative ICF

```bash
# Using rake task
bundle exec rake analysis:ocf_icf_gap
```

```ruby
# Using model scopes
companies = Company.with_positive_ocf_negative_icf
                   .with_positive_ocf_icf_gap

# Using analyzer service
companies = CompanyAnalyzer.find_cash_flow_positive_companies
turnaround = CompanyAnalyzer.find_gap_turnaround_companies(periods: 4)
```

### Use Case 3: Analyze Historical Metrics Before Breakthrough

```bash
# Using rake task
bundle exec rake analysis:historical_metrics[7203]
```

```ruby
# Using analyzer service
company = Company.find_by(code: "7203")
analysis = CompanyAnalyzer.analyze_breakthrough_precursors(
  company,
  breakthrough_year: 2024,
  breakthrough_period: "Q4",
  lookback_periods: 8
)
```

## Additional Features

### Query Scopes

```ruby
# High ROE companies
Company.high_roe(15)

# By industry
Company.by_industry("自動車・輸送機")

# By market
Company.by_market("Prime")

# Consecutive growth
Company.with_consecutive_revenue_growth(6)
Company.with_consecutive_profit_growth(6)
```

### Company Instance Methods

```ruby
company = Company.find_by(code: "7203")

# Latest data
company.latest_financial_statement
company.latest_stock_price

# Trends
company.growth_trend(periods: 4)
company.profitability_trend(periods: 4)
company.cash_flow_trend(periods: 4)

# Checks
company.consecutive_revenue_growth?(periods: 6)
company.consecutive_profit_growth?(periods: 6)

# Summary
company.metrics_summary
```

## API Clients

### EdinetClient
Access EDINET financial documents:
```ruby
client = EdinetClient.new
documents = client.document_list(date: "2024-03-31")
xbrl_data = client.download_xbrl(doc_id: "S100XXXX")
```

### JquantsClient
Access JQUANTS stock market data:
```ruby
client = JquantsClient.new
companies = client.listed_companies
prices = client.stock_prices(code: "7203", from: "2024-01-01", to: "2024-12-31")
statements = client.financial_statements(code: "7203")
```

## Project Structure

- `app/lib/`: Reusable API client libraries
  - `edinet_client.rb`: EDINET API client
  - `jquants_client.rb`: JQUANTS API client
- `app/jobs/`: Background jobs for data import and processing
  - `import_companies_job.rb`
  - `import_stock_prices_job.rb`
  - `import_financial_statements_job.rb`
  - `calculate_metrics_job.rb`
- `app/services/`: Business logic services
  - `metric_calculator.rb`: Calculates derived metrics from financial data
- `app/models/`: ActiveRecord models for database tables
