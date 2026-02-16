require "test_helper"

class FinancialStatementTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(code: "7203", name: "Toyota Motor Corporation")
    @statement = FinancialStatement.create!(
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
  end

  test "validates presence of fiscal_year" do
    fs = FinancialStatement.new(company: @company, fiscal_period: "FY")
    assert_not fs.valid?
    assert_includes fs.errors[:fiscal_year], "can't be blank"
  end

  test "validates presence of fiscal_period" do
    fs = FinancialStatement.new(company: @company, fiscal_year: 2025)
    assert_not fs.valid?
    assert_includes fs.errors[:fiscal_period], "can't be blank"
  end

  test "validates uniqueness of fiscal_year scoped to company and period" do
    duplicate = FinancialStatement.new(
      company: @company,
      fiscal_year: 2024,
      fiscal_period: "FY"
    )
    assert_not duplicate.valid?
  end

  test "allows same fiscal_year for different periods" do
    q1 = FinancialStatement.new(
      company: @company,
      fiscal_year: 2024,
      fiscal_period: "1Q"
    )
    assert q1.valid?
  end

  test "eps calculation" do
    assert_in_delta 3.5, @statement.eps, 0.01
  end

  test "eps returns nil when shares_outstanding is zero" do
    @statement.shares_outstanding = 0
    assert_nil @statement.eps
  end

  test "eps returns nil when net_income is nil" do
    @statement.net_income = nil
    assert_nil @statement.eps
  end

  test "annual scope" do
    assert_includes FinancialStatement.annual, @statement
    q1 = FinancialStatement.create!(company: @company, fiscal_year: 2024, fiscal_period: "1Q")
    assert_not_includes FinancialStatement.annual, q1
  end
end
