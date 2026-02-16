require "test_helper"

class CompanyTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(code: "7203", name: "Toyota Motor Corporation", market: "Prime", industry: "Transportation equipment", sector: "Automobile")
  end

  test "validates presence of code" do
    company = Company.new(name: "Test Corp")
    assert_not company.valid?
    assert_includes company.errors[:code], "can't be blank"
  end

  test "validates presence of name" do
    company = Company.new(code: "9999")
    assert_not company.valid?
    assert_includes company.errors[:name], "can't be blank"
  end

  test "validates uniqueness of code" do
    duplicate = Company.new(code: "7203", name: "Duplicate Corp")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:code], "has already been taken"
  end

  test "has many financial_statements" do
    assert_respond_to @company, :financial_statements
    assert_equal 0, @company.financial_statements.count
  end

  test "has many stock_prices" do
    assert_respond_to @company, :stock_prices
  end

  test "has many growth_metrics" do
    assert_respond_to @company, :growth_metrics
  end

  test "has many profitability_metrics" do
    assert_respond_to @company, :profitability_metrics
  end

  test "has many valuation_metrics" do
    assert_respond_to @company, :valuation_metrics
  end

  test "has many cash_flow_metrics" do
    assert_respond_to @company, :cash_flow_metrics
  end

  test "by_market scope" do
    assert_includes Company.by_market("Prime"), @company
    assert_not_includes Company.by_market("Standard"), @company
  end

  test "by_industry scope" do
    assert_includes Company.by_industry("Transportation equipment"), @company
  end

  test "by_sector scope" do
    assert_includes Company.by_sector("Automobile"), @company
  end

  test "search_by_name scope" do
    assert_includes Company.search_by_name("Toyota"), @company
    assert_not_includes Company.search_by_name("Honda"), @company
  end
end
