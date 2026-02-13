class CalculateMetricsJob < ApplicationJob
  queue_as :default

  # Calculate metrics for a specific company and fiscal period
  # @param company_id [Integer] Company ID
  # @param fiscal_year [Integer] Fiscal year
  # @param fiscal_period [String] Fiscal period
  def perform(company_id:, fiscal_year:, fiscal_period:)
    company = Company.find(company_id)
    calculator = MetricCalculator.new(company)

    calculator.calculate_all_metrics(
      fiscal_year: fiscal_year,
      fiscal_period: fiscal_period
    )

    Rails.logger.info "Metrics calculated for #{company.name} (#{fiscal_year}/#{fiscal_period})"
  end

  # Calculate metrics for all companies with financial statements
  def self.calculate_all
    FinancialStatement.find_each do |statement|
      CalculateMetricsJob.perform_later(
        company_id: statement.company_id,
        fiscal_year: statement.fiscal_year,
        fiscal_period: statement.fiscal_period
      )
    end
  end
end
