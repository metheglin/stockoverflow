namespace :analysis do
  desc "Find companies with consecutive revenue growth (PERIODS=6)"
  task revenue_growth: :environment do
    periods = (ENV["PERIODS"] || 6).to_i
    puts "Finding companies with #{periods}+ consecutive periods of revenue growth..."
    results = Company.with_consecutive_revenue_growth(periods)

    if results.empty?
      puts "No companies found."
    else
      puts "\n%-6s %-30s %8s %10s %s" % ["Code", "Name", "Periods", "Avg Growth", "Years"]
      puts "-" * 80
      results.each do |r|
        puts "%-6s %-30s %8d %9.1f%% %s" % [
          r[:company].code,
          r[:company].name.truncate(30),
          r[:consecutive_periods],
          r[:average_growth] * 100,
          r[:years].join(", ")
        ]
      end
    end
  end

  desc "Find companies with cash flow turnaround pattern"
  task cash_flow_turnaround: :environment do
    puts "Finding companies with cash flow turnaround..."
    results = Company.with_cash_flow_turnaround

    if results.empty?
      puts "No companies found."
    else
      puts "\n%-6s %-30s %12s %15s %12s" % ["Code", "Name", "Turn Year", "Latest FCF", "OCF/Sales"]
      puts "-" * 80
      results.each do |r|
        puts "%-6s %-30s %12d %15s %11.1f%%" % [
          r[:company].code,
          r[:company].name.truncate(30),
          r[:turnaround_year],
          number_with_delimiter(r[:latest_fcf]),
          (r[:latest_ocf_to_sales] || 0) * 100
        ]
      end
    end
  end

  desc "Show detailed profile for a company (CODE=7203)"
  task company_profile: :environment do
    code = ENV["CODE"]
    unless code
      puts "Usage: rake analysis:company_profile CODE=7203"
      exit 1
    end

    company = Company.find_by(code: code)
    unless company
      puts "Company not found: #{code}"
      exit 1
    end

    profile = company.profile
    puts "\n=== Company Profile ==="
    puts "Code: #{profile[:company][:code]}"
    puts "Name: #{profile[:company][:name]}"
    puts "Market: #{profile[:company][:market]}"
    puts "Industry: #{profile[:company][:industry]}"
    puts "Sector: #{profile[:company][:sector]}"

    if profile[:financials].any?
      puts "\n--- Financial Summary ---"
      puts "%-6s %15s %15s %15s" % ["Year", "Net Sales", "Op Income", "Net Income"]
      profile[:financials].each do |f|
        puts "%-6d %15s %15s %15s" % [
          f[:fiscal_year],
          number_with_delimiter(f[:net_sales]),
          number_with_delimiter(f[:operating_income]),
          number_with_delimiter(f[:net_income])
        ]
      end
    end

    if profile[:profitability].any?
      puts "\n--- Profitability ---"
      puts "%-6s %8s %8s %10s %10s" % ["Year", "ROE", "ROA", "Op Margin", "Net Margin"]
      profile[:profitability].each do |p|
        puts "%-6d %7.1f%% %7.1f%% %9.1f%% %9.1f%%" % [
          p[:fiscal_year],
          (p[:roe] || 0) * 100,
          (p[:roa] || 0) * 100,
          (p[:operating_margin] || 0) * 100,
          (p[:net_margin] || 0) * 100
        ]
      end
    end

    if profile[:growth].any?
      puts "\n--- Growth Rates ---"
      puts "%-6s %12s %12s %12s" % ["Year", "Revenue", "Op Income", "Net Income"]
      profile[:growth].each do |g|
        puts "%-6d %11.1f%% %11.1f%% %11.1f%%" % [
          g[:fiscal_year],
          (g[:revenue_growth] || 0) * 100,
          (g[:operating_income_growth] || 0) * 100,
          (g[:net_income_growth] || 0) * 100
        ]
      end
    end

    if profile[:cash_flow].any?
      puts "\n--- Cash Flow ---"
      puts "%-6s %15s %10s" % ["Year", "Free CF", "OCF/Sales"]
      profile[:cash_flow].each do |cf|
        puts "%-6d %15s %9.1f%%" % [
          cf[:fiscal_year],
          number_with_delimiter(cf[:free_cash_flow]),
          (cf[:ocf_to_sales] || 0) * 100
        ]
      end
    end
  end
end

def number_with_delimiter(number)
  return "N/A" if number.nil?
  number.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
end
