require "test_helper"

class MetricCalculatorTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(code: "7203", name: "Toyota Motor Corporation")

    # Create two years of financial statements for growth calculation
    @fs_2023 = FinancialStatement.create!(
      company: @company,
      fiscal_year: 2023,
      fiscal_period: "FY",
      net_sales: 40_000_000,
      operating_income: 4_000_000,
      net_income: 3_000_000,
      total_assets: 70_000_000,
      total_equity: 25_000_000,
      operating_cash_flow: 5_000_000,
      investing_cash_flow: -3_000_000,
      financing_cash_flow: -1_000_000,
      shares_outstanding: 1_000_000
    )

    @fs_2024 = FinancialStatement.create!(
      company: @company,
      fiscal_year: 2024,
      fiscal_period: "FY",
      net_sales: 45_000_000,
      operating_income: 5_000_000,
      net_income: 3_500_000,
      total_assets: 80_000_000,
      total_equity: 30_000_000,
      operating_cash_flow: 6_000_000,
      investing_cash_flow: -4_000_000,
      financing_cash_flow: -1_000_000,
      shares_outstanding: 1_000_000
    )

    @calculator = MetricCalculator.new(@company)
  end

  test "calculate_profitability_metrics creates records" do
    @calculator.calculate_profitability_metrics
    assert_equal 2, @company.profitability_metrics.count

    metric = @company.profitability_metrics.find_by(fiscal_year: 2024)
    assert_not_nil metric

    # ROE = net_income / total_equity = 3_500_000 / 30_000_000
    assert_in_delta 0.1167, metric.roe, 0.001

    # ROA = net_income / total_assets = 3_500_000 / 80_000_000
    assert_in_delta 0.0438, metric.roa, 0.001

    # Operating margin = operating_income / net_sales = 5_000_000 / 45_000_000
    assert_in_delta 0.1111, metric.operating_margin, 0.001

    # Net margin = net_income / net_sales = 3_500_000 / 45_000_000
    assert_in_delta 0.0778, metric.net_margin, 0.001
  end

  test "calculate_growth_metrics creates records" do
    @calculator.calculate_growth_metrics
    # Only 2024 should have growth (needs prior year)
    assert_equal 1, @company.growth_metrics.count

    metric = @company.growth_metrics.find_by(fiscal_year: 2024)
    assert_not_nil metric

    # Revenue growth = (45M - 40M) / 40M = 0.125
    assert_in_delta 0.125, metric.revenue_growth_rate, 0.001

    # Operating income growth = (5M - 4M) / 4M = 0.25
    assert_in_delta 0.25, metric.operating_income_growth_rate, 0.001

    # Net income growth = (3.5M - 3M) / 3M = 0.1667
    assert_in_delta 0.1667, metric.net_income_growth_rate, 0.001
  end

  test "calculate_cash_flow_metrics creates records" do
    @calculator.calculate_cash_flow_metrics
    assert_equal 2, @company.cash_flow_metrics.count

    metric = @company.cash_flow_metrics.find_by(fiscal_year: 2024)
    assert_not_nil metric

    # FCF = OCF + ICF = 6M + (-4M) = 2M
    assert_equal 2_000_000, metric.free_cash_flow

    # OCF/Sales = 6M / 45M
    assert_in_delta 0.1333, metric.ocf_to_sales, 0.001
  end

  test "calculate_valuation_metrics creates records" do
    StockPrice.create!(
      company: @company,
      date: Date.new(2024, 12, 31),
      close_price: 3500,
      open_price: 3400,
      high_price: 3600,
      low_price: 3300,
      volume: 1_000_000
    )

    @calculator.calculate_valuation_metrics

    metric = @company.valuation_metrics.find_by(date: Date.new(2024, 12, 31))
    assert_not_nil metric

    # PER = price / EPS = 3500 / 3.5 = 1000
    assert_in_delta 1000, metric.per, 1

    # Market cap = price * shares = 3500 * 1_000_000 = 3_500_000_000
    assert_equal 3_500_000_000, metric.market_cap
  end

  test "calculate_all runs all calculations" do
    StockPrice.create!(
      company: @company,
      date: Date.new(2024, 12, 31),
      close_price: 3500,
      open_price: 3400,
      high_price: 3600,
      low_price: 3300,
      volume: 1_000_000
    )

    @calculator.calculate_all

    assert @company.profitability_metrics.count > 0
    assert @company.growth_metrics.count > 0
    assert @company.cash_flow_metrics.count > 0
    assert @company.valuation_metrics.count > 0
  end

  test "handles nil values gracefully" do
    FinancialStatement.create!(
      company: @company,
      fiscal_year: 2025,
      fiscal_period: "FY",
      net_sales: nil,
      operating_income: nil,
      net_income: nil,
      total_assets: nil,
      total_equity: nil
    )

    assert_nothing_raised { @calculator.calculate_all }
  end

  test "idempotent - running twice produces same results" do
    @calculator.calculate_profitability_metrics
    count_first = @company.profitability_metrics.count

    @calculator.calculate_profitability_metrics
    count_second = @company.profitability_metrics.count

    assert_equal count_first, count_second
  end
end
