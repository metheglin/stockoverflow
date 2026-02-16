namespace :stock_data do
  desc "Import listed companies from J-Quants API"
  task import_companies: :environment do
    puts "Importing companies..."
    result = ImportCompaniesJob.perform_now
    puts "Done. Imported: #{result[:imported]}, Skipped: #{result[:skipped]}"
  end

  desc "Import financial statements from J-Quants API (optional CODE=7203)"
  task import_statements: :environment do
    code = ENV["CODE"]
    puts "Importing financial statements#{code ? " for #{code}" : ''}..."
    result = ImportFinancialStatementsJob.perform_now(code: code)
    puts "Done. Imported: #{result[:imported]}, Skipped: #{result[:skipped]}"
  end

  desc "Import stock prices from J-Quants API (optional CODE=7203, FROM=2024-01-01, TO=2024-12-31)"
  task import_prices: :environment do
    code = ENV["CODE"]
    from = ENV["FROM"]
    to = ENV["TO"]
    puts "Importing stock prices#{code ? " for #{code}" : ''}..."
    result = ImportStockPricesJob.perform_now(code: code, from: from, to: to)
    puts "Done. Imported: #{result[:imported]}, Skipped: #{result[:skipped]}"
  end

  desc "Calculate derived metrics for all companies (optional COMPANY_ID=1)"
  task calculate_metrics: :environment do
    company_id = ENV["COMPANY_ID"]
    puts "Calculating metrics..."
    CalculateMetricsJob.perform_now(company_id: company_id)
    puts "Done."
  end

  desc "Run full data pipeline: import companies, statements, prices, then calculate metrics"
  task refresh_all: :environment do
    Rake::Task["stock_data:import_companies"].invoke
    Rake::Task["stock_data:import_statements"].invoke
    Rake::Task["stock_data:import_prices"].invoke
    Rake::Task["stock_data:calculate_metrics"].invoke
    puts "Full refresh complete."
  end
end
