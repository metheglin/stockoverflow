class CalculateMetricsJob < ApplicationJob
  queue_as :default

  def perform(company_id: nil)
    companies = if company_id
      Company.where(id: company_id)
    else
      Company.all
    end

    companies.find_each do |company|
      Rails.logger.info "Calculating metrics for #{company.code} - #{company.name}"
      calculator = MetricCalculator.new(company)
      calculator.calculate_all
    end
  end
end
