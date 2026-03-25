namespace :benchmark do
  desc "Run query performance benchmarks against main analytical query patterns"
  task queries: :environment do
    connection = ActiveRecord::Base.connection

    puts "=== SQLite Pragma Settings ==="
    %w[journal_mode synchronous cache_size mmap_size].each do |pragma|
      result = connection.execute("PRAGMA #{pragma}")
      puts "  #{pragma}: #{result.first.values.first}"
    end
    puts ""

    puts "=== Table Row Counts ==="
    %w[companies financial_values financial_metrics daily_quotes financial_reports sector_metrics].each do |table|
      count = connection.execute("SELECT COUNT(*) AS cnt FROM #{table}").first["cnt"]
      puts "  #{table}: #{count}"
    end
    puts ""

    sample_company_id = connection.execute(
      "SELECT id FROM companies LIMIT 1"
    ).first&.fetch("id")

    unless sample_company_id
      puts "No data in companies table. Insert data first to run benchmarks."
      exit
    end

    queries = {
      "Timeline: metrics by company" => {
        sql: "SELECT * FROM financial_metrics WHERE company_id = ? AND scope = 0 AND period_type = 1 ORDER BY fiscal_year_end",
        binds: [sample_company_id],
      },
      "Timeline: values by company" => {
        sql: "SELECT * FROM financial_values WHERE company_id = ? AND scope = 0 AND period_type = 1 ORDER BY fiscal_year_end",
        binds: [sample_company_id],
      },
      "Screening: consecutive revenue growth >= 3" => {
        sql: "SELECT fm.*, c.name FROM financial_metrics fm JOIN companies c ON c.id = fm.company_id WHERE fm.scope = 0 AND fm.period_type = 1 AND fm.consecutive_revenue_growth >= 3 ORDER BY fm.revenue_yoy DESC",
        binds: [],
      },
      "Screening: consecutive profit growth >= 5" => {
        sql: "SELECT fm.*, c.name FROM financial_metrics fm JOIN companies c ON c.id = fm.company_id WHERE fm.scope = 0 AND fm.period_type = 1 AND fm.consecutive_profit_growth >= 5 ORDER BY fm.operating_income_yoy DESC",
        binds: [],
      },
      "Cash flow: positive operating CF & negative investing CF" => {
        sql: "SELECT fm.*, c.name FROM financial_metrics fm JOIN companies c ON c.id = fm.company_id WHERE fm.scope = 0 AND fm.period_type = 1 AND fm.operating_cf_positive = 1 AND fm.investing_cf_negative = 1",
        binds: [],
      },
      "Daily quotes: 1 year range" => {
        sql: "SELECT * FROM daily_quotes WHERE company_id = ? AND traded_on BETWEEN '2025-01-01' AND '2025-12-31' ORDER BY traded_on",
        binds: [sample_company_id],
      },
    }

    iterations = ENV.fetch("ITERATIONS", 10).to_i
    puts "=== Query Benchmarks (#{iterations} iterations each) ==="
    puts ""

    queries.each do |label, config|
      bound_sql = config[:sql].dup
      config[:binds].each { |v| bound_sql.sub!("?", v.to_s) }

      explain_result = connection.execute("EXPLAIN QUERY PLAN #{bound_sql}")
      plan = explain_result.map { |row| row["detail"] }.join("; ")

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      iterations.times { connection.execute(bound_sql) }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      row_count = connection.execute(bound_sql).length
      avg_ms = (elapsed / iterations * 1000).round(3)

      puts label
      puts "  Plan:    #{plan}"
      puts "  Rows:    #{row_count}"
      puts "  Avg:     #{avg_ms} ms"
      puts "  Total:   #{(elapsed * 1000).round(3)} ms (#{iterations} iterations)"
      puts ""
    end
  end
end
