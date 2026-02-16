require "test_helper"

class ImportCompaniesJobTest < ActiveSupport::TestCase
  test "job class exists and is an ApplicationJob" do
    assert_kind_of Class, ImportCompaniesJob
    assert ImportCompaniesJob < ApplicationJob
  end

  test "job responds to perform" do
    assert ImportCompaniesJob.method_defined?(:perform)
  end
end

class ImportStockPricesJobTest < ActiveSupport::TestCase
  test "job class exists and is an ApplicationJob" do
    assert_kind_of Class, ImportStockPricesJob
    assert ImportStockPricesJob < ApplicationJob
  end

  test "job responds to perform" do
    assert ImportStockPricesJob.method_defined?(:perform)
  end
end

class ImportFinancialStatementsJobTest < ActiveSupport::TestCase
  test "job class exists and is an ApplicationJob" do
    assert_kind_of Class, ImportFinancialStatementsJob
    assert ImportFinancialStatementsJob < ApplicationJob
  end

  test "job responds to perform" do
    assert ImportFinancialStatementsJob.method_defined?(:perform)
  end
end

class CalculateMetricsJobTest < ActiveSupport::TestCase
  test "job class exists and is an ApplicationJob" do
    assert_kind_of Class, CalculateMetricsJob
    assert CalculateMetricsJob < ApplicationJob
  end

  test "perform with no data does not raise" do
    assert_nothing_raised { CalculateMetricsJob.perform_now }
  end

  test "perform with company_id calculates for specific company" do
    company = Company.create!(code: "9999", name: "Test Corp")
    FinancialStatement.create!(
      company: company,
      fiscal_year: 2024,
      fiscal_period: "FY",
      net_sales: 100_000,
      operating_income: 10_000,
      net_income: 7_000,
      total_assets: 200_000,
      total_equity: 80_000
    )

    assert_nothing_raised { CalculateMetricsJob.perform_now(company_id: company.id) }
    assert company.profitability_metrics.count > 0
  end
end
