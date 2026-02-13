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

## Use Cases

### Find Companies with Consecutive Revenue/Profit Growth
```ruby
# Companies with 6 consecutive periods of revenue growth
companies = Company.joins(:growth_metrics)
  .group("companies.id")
  .having("COUNT(CASE WHEN growth_metrics.revenue_growth_rate > 0 THEN 1 END) >= 6")
  .order("AVG(growth_metrics.revenue_growth_rate) DESC")
```

### Find Companies with Positive OCF and Negative ICF
```ruby
# Companies with OCF+ and ICF- and positive gap
companies = Company.joins(:cash_flow_metrics)
  .joins(:financial_statements)
  .where("financial_statements.operating_cash_flow > 0")
  .where("financial_statements.investing_cash_flow < 0")
  .where("cash_flow_metrics.ocf_icf_gap > 0")
```

### Analyze Historical Metrics Before Breakthrough
```ruby
# Get historical profitability metrics for a company
company = Company.find_by(code: "7203")
metrics = company.profitability_metrics.order(fiscal_year: :asc)

# Analyze growth trajectory
growth_history = company.growth_metrics.order(fiscal_year: :asc)
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
