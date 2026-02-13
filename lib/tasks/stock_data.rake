namespace :stock_data do
  desc "Import all companies from JQUANTS"
  task import_companies: :environment do
    puts "Importing companies from JQUANTS..."
    ImportCompaniesJob.perform_now
    puts "Company import completed!"
    puts "Total companies: #{Company.count}"
  end

  desc "Import financial statements for all companies or specific company"
  task :import_statements, [:code, :date] => :environment do |t, args|
    puts "Importing financial statements..."

    if args[:code]
      puts "  For company code: #{args[:code]}"
      ImportFinancialStatementsJob.perform_now(code: args[:code])
    elsif args[:date]
      puts "  For date: #{args[:date]}"
      ImportFinancialStatementsJob.perform_now(date: args[:date])
    else
      puts "  For all companies"
      ImportFinancialStatementsJob.perform_now
    end

    puts "Financial statements import completed!"
    puts "Total statements: #{FinancialStatement.count}"
  end

  desc "Import stock prices for a date range"
  task :import_prices, [:from, :to, :code] => :environment do |t, args|
    from = args[:from] || (Date.today - 365).strftime("%Y-%m-%d")
    to = args[:to] || Date.today.strftime("%Y-%m-%d")

    puts "Importing stock prices..."
    puts "  Date range: #{from} to #{to}"
    puts "  Company code: #{args[:code] || 'all'}"

    ImportStockPricesJob.perform_now(from: from, to: to, code: args[:code])

    puts "Stock prices import completed!"
    puts "Total price records: #{StockPrice.count}"
  end

  desc "Calculate metrics for all companies with financial statements"
  task calculate_metrics: :environment do
    puts "Calculating metrics for all companies..."

    count = 0
    FinancialStatement.find_each do |statement|
      calculator = MetricCalculator.new(statement.company)
      calculator.calculate_all_metrics(
        fiscal_year: statement.fiscal_year,
        fiscal_period: statement.fiscal_period
      )
      count += 1
      print "." if count % 10 == 0
    end

    puts "\nMetrics calculation completed!"
    puts "Growth metrics: #{GrowthMetric.count}"
    puts "Profitability metrics: #{ProfitabilityMetric.count}"
    puts "Cash flow metrics: #{CashFlowMetric.count}"
  end

  desc "Calculate valuation metrics based on stock prices"
  task :calculate_valuations, [:date] => :environment do |t, args|
    date = args[:date] ? Date.parse(args[:date]) : Date.today

    puts "Calculating valuation metrics for date: #{date}"

    Company.joins(:stock_prices).where(stock_prices: { date: date }).distinct.find_each do |company|
      calculator = MetricCalculator.new(company)
      calculator.calculate_valuation_metrics(date: date)
      print "."
    end

    puts "\nValuation metrics calculation completed!"
    puts "Total valuation metrics: #{ValuationMetric.count}"
  end

  desc "Full data refresh: import companies, statements, prices, and calculate metrics"
  task :refresh_all, [:from, :to] => :environment do |t, args|
    from = args[:from] || (Date.today - 365).strftime("%Y-%m-%d")
    to = args[:to] || Date.today.strftime("%Y-%m-%d")

    puts "=== Starting full data refresh ==="

    puts "\n1. Importing companies..."
    Rake::Task["stock_data:import_companies"].invoke

    puts "\n2. Importing financial statements..."
    Rake::Task["stock_data:import_statements"].invoke

    puts "\n3. Importing stock prices..."
    Rake::Task["stock_data:import_prices"].invoke(from, to)

    puts "\n4. Calculating metrics..."
    Rake::Task["stock_data:calculate_metrics"].invoke

    puts "\n5. Calculating valuations..."
    Rake::Task["stock_data:calculate_valuations"].invoke(to)

    puts "\n=== Data refresh completed! ==="
  end
end
